"""Host controls for the pending Angel/Bob F210 native steel witness.

The controls exercise the fixture's own data/runtime guards only.  They do
not start Factorio, create a profile, or qualify native gameplay/save output.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "angelbob-f210-steel"
NAME = "mir-fixture-mir5-angelbob-f210-steel"
OWNER = "steel-plate-productivity"
RECIPES = ("steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2")
SCIENCE = ("automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack")
STRICT_MODS = {
    "base": "2.1.23", "elevated-rails": "2.1.23", "quality": "2.1.23", "recycler": "2.1.23",
    "space-age": "2.1.23", "angelbob-spaceage-rebalance": "1.3.2",
    "angelsbioprocessing": "2.1.1", "angelsbioprocessinggraphics": "2.1.0",
    "angelspetrochem": "2.1.3", "angelspetrochemgraphics": "2.1.0",
    "angelsrefining": "2.1.2", "angelsrefininggraphics": "2.1.0",
    "angelssmelting": "2.1.1", "angelssmeltinggraphics": "2.1.1",
    "bobassembly": "3.0.1", "bobelectronics": "3.0.1", "boblibrary": "3.0.1",
    "boblogistics": "3.0.1", "bobmodules": "3.0.1", "bobores": "3.0.0", "bobplates": "3.0.2",
    "bobpower": "3.0.0", "bobrevamp": "3.0.0", "bobtech": "3.0.0",
    "more-infinite-research": "5.0.21013", NAME: "0.1.0",
}

_package_spec = importlib.util.spec_from_file_location("angelbob_steel_package", ROOT / "tools" / "package.py")
PACKAGE = importlib.util.module_from_spec(_package_spec)
assert _package_spec.loader is not None
_package_spec.loader.exec_module(PACKAGE)


def plain(value):
    if not hasattr(value, "items"):
        return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) for key in keys):
        return [plain(value[index]) for index in range(1, max(keys) + 1)]
    return {key: plain(item) for key, item in value.items()}


def lua_value(runtime, value):
    if isinstance(value, dict):
        table = runtime.table()
        for key, item in value.items():
            table[key] = lua_value(runtime, item)
        return table
    if isinstance(value, (list, tuple)):
        table = runtime.table()
        for index, item in enumerate(value, 1):
            table[index] = lua_value(runtime, item)
        return table
    return value


def owner_raw(opponent: str = ""):
    effects = [{"type": "unlock-recipe", "recipe": "foreign-unlock"}] + [
        {"type": "change-recipe-productivity", "recipe": name, "change": .1} for name in RECIPES
    ]
    row = {
        "type": "technology", "name": OWNER, "max_level": "infinite",
        "prerequisites": ["production-science-pack"],
        "effects": effects,
        "unit": {"count_formula": "1.5^L*1000", "time": 60,
                 "ingredients": [[name, 1] for name in SCIENCE]},
        "foreign_marker": {"preserve": "verbatim"},
    }
    if opponent == "missing":
        row["effects"] = row["effects"][:-1]
    elif opponent == "duplicate":
        row["effects"].append(deepcopy(row["effects"][-1]))
    elif opponent == "wrong-change":
        row["effects"][-1]["change"] = .2
    elif opponent == "wrong-cost":
        row["unit"]["time"] = 30
    elif opponent == "wrong-pack":
        row["unit"]["ingredients"][-1][0] = "utility-science-pack"
    return row


class AngelBobF210SteelFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(LUA_RUNTIME_DIR.resolve(strict=True)))
        from lupa.lua52 import LuaRuntime
        cls.LuaRuntime = LuaRuntime

    def setUp(self):
        self.lua = self.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.execute(r'''
function run_data(raw, active_mods)
  local cache={}
  local env={data={raw=raw},mods=active_mods}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
    if cache[name] then return cache[name] end
    local chunk,message=loadfile(fixture.."/fixture_facts.lua","t",env);assert(chunk,message)
    cache[name]=chunk();return cache[name]
  end
  env._G=env;setmetatable(env,{__index=_G})
  local chunk,message=loadfile(fixture.."/data-final-fixes.lua","t",env);assert(chunk,message)
  local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),raw=raw}
end

function parse_control()
  local callbacks,reads={events={}}, {game=0,storage=0}
  local env={script={active_mods={},on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
    on_event=function(event,fn)callbacks.events[event]=fn end},defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
    local chunk,message=loadfile(fixture.."/fixture_facts.lua","t",env);assert(chunk,message);return chunk()
  end
  env._G=env;setmetatable(env,{__index=function(_,key) if reads[key]~=nil then reads[key]=reads[key]+1 end;return _G[key] end})
  local chunk,message=loadfile(fixture.."/control.lua","t",env);assert(chunk,message)
  local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end

function run_control(active_mods, opponent, supplied_baselines)
  local markers,saves,settling_markers={},0,0
  supplied_baselines=supplied_baselines or {}
  local effects={{type="unlock-recipe",recipe="foreign-unlock"}}
  local recipe_names={"steel-plate","casting-steel","angels-plate-steel","angels-plate-steel-2"}
  for _,name in ipairs(recipe_names) do effects[#effects+1]={type="change-recipe-productivity",recipe=name,change=.1} end
  if opponent=="missing" then table.remove(effects,#effects) end
  if opponent=="duplicate" then effects[#effects+1]={type="change-recipe-productivity",recipe="angels-plate-steel-2",change=.1} end
  if opponent=="wrong-change" then effects[#effects].change=.2 end
  local owner={name="steel-plate-productivity",valid=true,enabled=true,researched=false,level=1,
    prototype={level=1,max_level=4294967295,research_unit_count_formula="1.5^L*1000",effects=effects},
    research_unit_count=opponent=="wrong-count" and 1499 or 1500,research_unit_energy=opponent=="wrong-energy" and 60 or 3600,
    research_unit_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},
      {name="chemical-science-pack",amount=1},{name="production-science-pack",amount=1}}}
  if opponent=="wrong-pack" then owner.research_unit_ingredients[4].name="utility-science-pack" end
  local prerequisite={name="production-science-pack",valid=true,enabled=true,researched=false}
  local player={technologies={["steel-plate-productivity"]=owner,["production-science-pack"]=prerequisite},recipes={},
    laboratory_speed_modifier=0,laboratory_productivity_bonus=0,current_research=nil}
  for index,name in ipairs(recipe_names) do
    local baseline=supplied_baselines[name] or 0
    if opponent=="negative-baseline" and index==1 then baseline=-.1 end
    if opponent=="nonfinite-baseline" and index==1 then baseline=math.huge end
    player.recipes[name]={productivity_bonus=baseline}
  end
  owner.force=player
  if opponent=="prerequisite-lab-modifier" then
    prerequisite.researched=nil
    setmetatable(prerequisite,{__newindex=function(row,key,value)
      rawset(row,key,value)
      if key=="researched" then player.laboratory_productivity_bonus=.1 end
    end})
  end
  function player.add_research(value) player.current_research=value;return true end
  local counts={}
  local inventory={
    insert=function(stack) counts[stack.name]=(counts[stack.name] or 0)+stack.count;return stack.count end,
    get_item_count=function(name) return counts[name] or 0 end,
  }
  local lab={valid=true,quality={name="normal"},prototype={name="mir-fixture-mir5-angelbob-f210-steel-fast-lab",
      get_researching_speed=function(quality) assert(quality=="normal");return 6000 end},
    get_inventory=function(kind) assert(kind==1);return inventory end,disabled_by_script=false}
  local game={tick=0,forces={player=player},surfaces={[1]={create_entity=function(spec)
    assert(spec.name=="mir-fixture-mir5-angelbob-f210-steel-fast-lab" and spec.force==player);return lab end}}}
  function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
  local callbacks,storage={events={}},{}
  local env={game=game,storage=storage,helpers={table_to_json=function(row) markers[#markers+1]=row;return "{}" end},
    log=function() end,script={active_mods=active_mods,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
      on_event=function(event,fn)callbacks.events[event]=fn end},defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
  local cache={}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-angelbob-f210-steel__/fixture_facts")
    if cache[name] then return cache[name] end
    local chunk,message=loadfile(fixture.."/fixture_facts.lua","t",env);assert(chunk,message)
    cache[name]=chunk();return cache[name]
  end
  env._G=env;setmetatable(env,{__index=_G})
  local chunk,message=loadfile(fixture.."/control.lua","t",env);assert(chunk,message);chunk()
  local ok,result=pcall(callbacks.init)
  if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  game.tick=1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  local premature=#markers
  for tick=1,15 do
    counts["automation-science-pack"]=counts["automation-science-pack"]-100
    counts["logistic-science-pack"]=counts["logistic-science-pack"]-100
    counts["chemical-science-pack"]=counts["chemical-science-pack"]-100
    counts["production-science-pack"]=counts["production-science-pack"]-100
    if tick==15 then
      owner.level,owner.research_unit_count,owner.researched=2,2250,false;player.current_research=nil
      for _,name in ipairs(recipe_names) do
        local baseline=supplied_baselines[name] or 0
        if opponent=="double-delta" then player.recipes[name].productivity_bonus=baseline+.2
        elseif opponent=="lost-baseline" then player.recipes[name].productivity_bonus=.1
        else player.recipes[name].productivity_bonus=baseline+.1 end
      end
      ok,result=pcall(callbacks.events[1],{research=owner,by_script=opponent=="scripted"})
      if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
    end
    game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
    if tick==15 then settling_markers=#markers end
    if tick<15 then
      -- The next real update supplies only after an ordinary native debit.
      game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
    end
  end
  -- The fixture requires two full post-event ticks before a passed marker.
  game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
  local before_load_phase=storage.mir5_angelbob_f210_steel and storage.mir5_angelbob_f210_steel.phase
  callbacks.load();game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
  callbacks.load();game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers,premature=premature} end
  return {ok=true,saves=saves,markers=markers,premature=premature,settling_markers=settling_markers,
    phase=storage.mir5_angelbob_f210_steel.phase,
    before_load_phase=before_load_phase,counts=counts,disabled=lab.disabled_by_script}
end
''')

    def _data(self, opponent: str = "", mods=None):
        raw = {"technology": {OWNER: owner_raw(opponent)}}
        return plain(self.lua.eval("run_data")(lua_value(self.lua, raw), lua_value(self.lua, mods or STRICT_MODS)))

    def _control(self, opponent: str = "", mods=None, baselines=None):
        return plain(self.lua.eval("run_control")(lua_value(self.lua, mods or STRICT_MODS), opponent,
                                                   lua_value(self.lua, baselines or {})))

    def test_info_and_facts_freeze_the_exact_profile_worker_closure(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(NAME, info["name"])
        self.assertEqual("0.1.0", info["version"])
        self.assertEqual(["base >= 2.1.23", "more-infinite-research = 5.0.21013",
                          "angelbob-spaceage-rebalance = 1.3.2", "space-age >= 2.1.23"],
                         info["dependencies"][:4])
        declared = set(info["dependencies"])
        self.assertEqual({f"? {name} = {version}" for name, version in STRICT_MODS.items()
                          if name not in {"base", "more-infinite-research", "angelbob-spaceage-rebalance",
                                          "space-age", NAME}}, declared - set(info["dependencies"][:4]))
        facts = (FIXTURE / "fixture_facts.lua").read_text(encoding="utf-8")
        self.assertIn('M.first_level_count = 1500', facts)
        self.assertIn('M.research_unit_energy = 3600', facts)
        self.assertIn('M.effect_change = .1', facts)
        self.assertNotIn("enable_all_prototypes", facts)

    def test_fixture_archive_is_owned_and_contains_no_player_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / f"{NAME}_0.1.0.zip"
            record = PACKAGE.build(FIXTURE, archive)
            self.assertTrue(archive.samefile(Path(record["archive"])))
            self.assertEqual((NAME, "0.1.0"), (record["name"], record["version"]))
            self.assertEqual({"info.json", "fixture_facts.lua", "data.lua", "data-final-fixes.lua", "control.lua"},
                             {row["path"] for row in record["members"]})
            with zipfile.ZipFile(archive) as package:
                names = set(package.namelist())
            self.assertFalse(any("source/" in name or "spec/" in name for name in names))

    def test_data_preflight_preserves_foreign_fields_and_accepts_broader_effects(self):
        result = self._data()
        self.assertTrue(result["ok"], result["message"])
        owner = result["raw"]["technology"][OWNER]
        self.assertNotIn("level", owner)  # native raw defaults level one at runtime
        self.assertEqual({"preserve": "verbatim"}, owner["foreign_marker"])
        self.assertEqual("foreign-unlock", owner["effects"][0]["recipe"])
        self.assertEqual(5, len(owner["effects"]))
        source = (FIXTURE / "data-final-fixes.lua").read_text(encoding="utf-8")
        self.assertNotIn("owner.effects =", source)
        self.assertNotIn("owner.unit =", source)
        self.assertNotIn("owner.prerequisites =", source)

    def test_data_preflight_refuses_wrong_missing_duplicate_or_changed_named_owner_rows(self):
        for opponent, phrase in (
            ("missing", "named productivity effect count differs"),
            ("duplicate", "named productivity effect count differs"),
            ("wrong-change", "named productivity change differs"),
            ("wrong-cost", "native steel owner identity or ordinary cost differs"),
            ("wrong-pack", "native steel ingredients differs"),
        ):
            with self.subTest(opponent=opponent):
                result = self._data(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
        wrong = dict(STRICT_MODS)
        wrong["bobtech"] = "3.0.1"
        result = self._data(mods=wrong)
        self.assertFalse(result["ok"])
        self.assertIn("declared closure differs: bobtech", result["message"])

    def test_control_registers_lifecycle_without_parse_time_game_or_storage_access(self):
        result = plain(self.lua.eval("parse_control")())
        self.assertTrue(result["ok"], result["message"])
        self.assertEqual({"game": 0, "storage": 0}, result["reads"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual(2, len(result["callbacks"]["events"]))
        self.assertIsNotNone(result["callbacks"]["events"][0])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", on_load)
        self.assertNotIn("server_save", on_load)
        self.assertNotIn("owner.level =", source)
        self.assertNotIn("owner.researched =", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("research_all", source)
        self.assertIn('get_researching_speed("normal")', source)
        self.assertNotIn("native_productivity_delta=.1", source)
        self.assertIn("named_productivity_deltas=frame.deltas", source)

    def test_real_lab_contract_counts_one_unscripted_completion_payment_save_and_cold_reads(self):
        result = self._control()
        self.assertTrue(result["ok"], result.get("message", ""))
        self.assertEqual((0, 0, 1, "complete", "complete", True),
                         (result["premature"], result["settling_markers"], result["saves"], result["phase"],
                          result["before_load_phase"], result["disabled"]))
        self.assertEqual(["initial", "reload", "reload"], [row["stage"] for row in result["markers"]])
        for marker in result["markers"]:
            witness = marker["witnesses"]
            self.assertEqual(1, witness["actual_steel_laboratory_completions"])
            self.assertFalse(witness["event_by_script"])
            self.assertEqual(1, witness["named_effect_count_each"])
            self.assertEqual(list(RECIPES), witness["named_steel_recipes"])
            self.assertEqual({name: 0 for name in RECIPES}, witness["named_productivity_baselines"])
            self.assertEqual({name: .1 for name in RECIPES}, witness["named_productivity_deltas"])
            self.assertEqual({name: .1 for name in RECIPES}, witness["named_productivity_bonuses"])
            self.assertEqual({name: 1500 for name in SCIENCE}, witness["actual_paid_science"])
            self.assertTrue(witness["broader_eligible_steel_recipes_unconstrained"])
            self.assertTrue(witness["prototype_baseline_capture_required"])
            self.assertFalse(witness["physical_output_qualified"])
        self.assertEqual({name: 100 for name in SCIENCE}, result["counts"])

    def test_distinct_foreign_productivity_baselines_are_preserved_with_one_native_delta_across_colds(self):
        baselines = {"steel-plate": .2, "casting-steel": .35, "angels-plate-steel": .4,
                     "angels-plate-steel-2": .55}
        result = self._control(baselines=baselines)
        self.assertTrue(result["ok"], result.get("message", ""))
        for marker in result["markers"]:
            witness = marker["witnesses"]
            self.assertEqual(baselines, witness["named_productivity_baselines"])
            for recipe in RECIPES:
                self.assertAlmostEqual(.1, witness["named_productivity_deltas"][recipe])
                self.assertAlmostEqual(baselines[recipe] + .1, witness["named_productivity_bonuses"][recipe])

    def test_runtime_refuses_scripted_completion_and_bad_named_owner_contract_before_save(self):
        for opponent, phrase in (
            ("scripted", "scripted steel completion cannot satisfy this fixture"),
            ("missing", "native steel named effect count differs"),
            ("duplicate", "native steel named effect count differs"),
            ("wrong-change", "native steel change differs"),
            ("wrong-count", "native steel first-level count differs"),
            ("wrong-energy", "native steel ordinary cost differs"),
            ("wrong-pack", "native steel ingredients is absent"),
            ("prerequisite-lab-modifier", "after prerequisite seed fixture requires unmodified force laboratory modifiers"),
            ("negative-baseline", "native productivity baseline differs"),
            ("nonfinite-baseline", "native productivity baseline differs"),
        ):
            with self.subTest(opponent=opponent):
                result = self._control(opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                self.assertEqual(0, result["saves"])
                self.assertFalse(any(row.get("status") == "passed" for row in result["markers"]))

    def test_runtime_refuses_double_delta_or_lost_foreign_baseline_before_save(self):
        baselines = {"steel-plate": .2, "casting-steel": .35, "angels-plate-steel": .4,
                     "angels-plate-steel-2": .55}
        for opponent in ("double-delta", "lost-baseline"):
            with self.subTest(opponent=opponent):
                result = self._control(opponent, baselines=baselines)
                self.assertFalse(result["ok"])
                self.assertIn("native productivity bonus differs", result["message"])
                self.assertEqual(0, result["saves"])
                self.assertFalse(any(row.get("status") == "passed" for row in result["markers"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", required=True, type=Path)
    args = parser.parse_args()
    LUA_RUNTIME_DIR = args.lua_runtime_dir.resolve(strict=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AngelBobF210SteelFixtureTests)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if outcome.wasSuccessful() else 1)
