"""Independent preparation controls for the F210 Bob/Angel science-and-oil fixture.

These controls use bounded upstream/published facts.  They prepare a native
gameplay/save case; they neither launch Factorio nor qualify the new rows.
"""

from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "bob-angel-f210-science-oil"
NAME = "mir-fixture-mir5-bob-angel-f210-science-oil"
ENGINE_SHA = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
MIR_SHA = "E3A65C08AC7798A66FB1BE30D24307B17C8B366DD901953BDE2A09BD6939C8CE"
OBSERVER_SHA = "A15A7D628D66953D2E0C4D4FA288F47CBF9C5678327C7EB3D23ADB5DC78331C0"
SOURCE = "b251ae7a54104ace87cb0da4cf531cf53f03c93d"
PLAYER_TREE = "79b73a6a8e68987737e69bf2d95ec6555b49f901"
SCIENCE = "recipe-prod-research_science_pack_productivity-1"
OIL = "recipe-prod-research_oil_cracking_productivity-1"
INPUT_REVISION = "c37fca88667d550660f5b9c0efd7f272b56d6025"
INPUT_RECEIPT = ROOT / "spec/evidence/bob-angel-f210-science-oil-inputs-c37fca88.json"
FIXTURE_ARCHIVE = "mir-fixture-mir5-bob-angel-f210-science-oil_0.1.0.zip"
FIXTURE_SHA = "3F02D963DD2B067DA54C4916DBF5F11B7E0D5C51A3856E5DF9B0D8108A8B7630"
FIXTURE_BYTES = 7825

BASE_VECTOR = [
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack", "military-science-pack",
    "angels-token-bio", "bob-advanced-logistic-science-pack",
]
SA_VECTOR = BASE_VECTOR[:6] + [
    "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
    "angels-token-bio", "bob-advanced-logistic-science-pack",
]
BASE_PREREQUISITES = [
    "research-speed-5", "utility-science-pack", "research-speed-6",
    "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
    "production-science-pack", "military-science-pack", "angels-gardens",
    "bob-advanced-logistic-science-pack",
]
SA_PREREQUISITES = BASE_PREREQUISITES[:8] + [
    "space-science-pack", "agricultural-science-pack", "metallurgic-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack", "promethium-science-pack",
    "angels-gardens", "bob-advanced-logistic-science-pack",
]
BASE_EFFECTS = [
    "automation-science-pack", "chemical-science-pack", "logistic-science-pack",
    "military-science-pack", "production-science-pack", "utility-science-pack",
    "angels-desert-garden-a", "angels-desert-garden-cultivating-a",
    "angels-swamp-garden-a", "angels-swamp-garden-cultivating-a",
    "angels-temperate-garden-a", "angels-temperate-garden-cultivating-a",
    "bob-advanced-logistic-science-pack", "bob-alien-science-pack",
    "bob-alien-science-pack-blue", "bob-alien-science-pack-green",
    "bob-alien-science-pack-orange", "bob-alien-science-pack-purple",
    "bob-alien-science-pack-red", "bob-alien-science-pack-yellow",
    "bob-science-pack-gold",
]
SA_EFFECTS = [
    "agricultural-science-pack", "automation-science-pack", "chemical-science-pack",
    "cryogenic-science-pack", "electromagnetic-science-pack", "logistic-science-pack",
    "metallurgic-science-pack", "military-science-pack", "production-science-pack",
    "promethium-science-pack", "space-science-pack", "utility-science-pack",
    "angels-desert-garden-a", "angels-desert-garden-cultivating-a",
    "angels-swamp-garden-a", "angels-swamp-garden-cultivating-a",
    "angels-temperate-garden-a", "angels-temperate-garden-cultivating-a",
    "bob-advanced-logistic-science-pack", "bob-alien-science-pack",
    "bob-alien-science-pack-blue", "bob-alien-science-pack-green",
    "bob-alien-science-pack-orange", "bob-alien-science-pack-purple",
    "bob-alien-science-pack-red", "bob-alien-science-pack-yellow",
    "bob-science-pack-gold",
]
OIL_EFFECTS = ["heavy-oil-cracking", "light-oil-cracking"]

_package_spec = importlib.util.spec_from_file_location("science_oil_package", ROOT / "tools" / "package.py")
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
    if isinstance(value, list):
        table = runtime.table()
        for index, item in enumerate(value, 1):
            table[index] = lua_value(runtime, item)
        return table
    return value


def effects(names):
    return [{"type": "change-recipe-productivity", "recipe": name, "change": .1} for name in names]


def raw_case(space_age: bool, opponent: str = ""):
    vector = SA_VECTOR if space_age else BASE_VECTOR
    prerequisites = SA_PREREQUISITES if space_age else BASE_PREREQUISITES
    science_effects = SA_EFFECTS if space_age else BASE_EFFECTS
    science = {
        "type": "technology", "name": SCIENCE, "level": 1, "upgrade": True,
        "max_level": "infinite", "order": "p[research_science_pack_productivity]",
        "icons": [
            {"icon": "__space-age__/graphics/technology/research-productivity.png" if space_age
             else "__base__/graphics/technology/space-science-pack.png", "icon_size": 256},
            {"icon": "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
             "icon_size": 128, "scale": .5, "floating": True, "shift": [50, 50]},
        ],
        "localised_name": ["technology-name.more-infinite-research.research_science_pack_productivity"],
        "localised_description": ["technology-description.more-infinite-research.recipe_productivity"],
        "prerequisites": deepcopy(prerequisites),
        "effects": effects(science_effects),
        "unit": {"count_formula": "8000*2^(L-1)", "time": 120,
                 "ingredients": [[name, 1] for name in vector]},
    }
    oil = {
        "type": "technology", "name": OIL, "level": 1, "upgrade": True,
        "max_level": "infinite", "order": "p[research_oil_cracking_productivity]",
        "enabled": False,
        "icons": [
            {"icon": "__base__/graphics/technology/oil-processing.png", "icon_size": 256},
            {"icon": "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
             "icon_size": 128, "scale": .5, "floating": True, "shift": [50, 50]},
        ],
        "localised_name": ["technology-name.more-infinite-research.research_oil_cracking_productivity"],
        "localised_description": ["technology-description.more-infinite-research.recipe_productivity"],
        "prerequisites": ["automation-science-pack", "logistic-science-pack"],
        "effects": effects(OIL_EFFECTS),
        "unit": {"count_formula": "8000*2^(L-1)", "time": 60,
                 "ingredients": [["automation-science-pack", 1], ["logistic-science-pack", 1]]},
    }
    if opponent == "science-effect":
        science["effects"][0]["change"] = .2
    elif opponent == "science-vector":
        science["unit"]["ingredients"][0][0] = "wrong-science-input"
    elif opponent == "science-prerequisite":
        science["prerequisites"][0] = "wrong-prerequisite"
    elif opponent == "oil-enabled":
        oil["enabled"] = True
    technologies = {SCIENCE: science, OIL: oil}
    for name in set(vector + prerequisites + ["automation"]):
        technologies.setdefault(name, {"name": name, "effects": [], "unit": {"ingredients": []}})
    items = {name: {"name": name} for name in vector}
    recipes = {name: {"name": name} for name in science_effects + OIL_EFFECTS}
    if opponent == "missing-producer":
        recipes.pop(science_effects[-1])
    return {"technology": technologies, "item": items, "recipe": recipes}


class BobAngelScienceOilFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(LUA_RUNTIME_DIR.resolve(strict=True)))
        from lupa.lua52 import LuaRuntime
        cls.LuaRuntime = LuaRuntime

    def setUp(self):
        self.lua = self.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture = FIXTURE.as_posix()
        self.lua.execute(r'''
function run_data(raw, mods)
  local cache = {}
  local env = {data={raw=raw},mods=mods}
  env.require = function(name)
    assert(name=="__mir-fixture-mir5-bob-angel-f210-science-oil__/fixture_facts")
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
  local callbacks, reads = {events={}}, {game=0,storage=0}
  local env={script={active_mods={},on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
    on_event=function(event,fn) callbacks.events[event]=fn end},defines={events={on_research_finished=1,on_tick=2}}}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-bob-angel-f210-science-oil__/fixture_facts")
    local chunk,message=loadfile(fixture.."/fixture_facts.lua","t",env);assert(chunk,message);return chunk()
  end
  env._G=env;setmetatable(env,{__index=function(_,key)
    if reads[key]~=nil then reads[key]=reads[key]+1 end
    return _G[key]
  end})
  local chunk,message=loadfile(fixture.."/control.lua","t",env);assert(chunk,message)
  local ok,result=pcall(chunk)
  return {ok=ok,message=tostring(result),callbacks=callbacks,reads=reads}
end

function run_control_model(mods, vector, prerequisites, effect_names, missing, tamper)
  local markers,saves={},0
  local function technology(name,effects,ingredients,prerequisites)
    local state={name=name,valid=true,level=1,researched=false,enabled=true,visible_when_disabled=false,
      saved_progress=0,prototype={max_level=4294967295,effects=effects or {}},
      research_unit_ingredients=ingredients or {},prerequisites=prerequisites or {}}
    return setmetatable({}, {__index=state,__newindex=function(_,key,value)
      state[key]=value
      if key=="level" then state.enabled=true end
    end})
  end
  local function new_force(name,index)
    local force={name=name,index=index,valid=true,technologies={},recipes={},research_queue={},research_progress=0}
    local science_effects,oil_effects={},{}
    for _,recipe in ipairs(effect_names) do
      science_effects[#science_effects+1]={type="change-recipe-productivity",recipe=recipe,change=.1}
      force.recipes[recipe]={productivity_bonus=0}
    end
    for _,recipe in ipairs({"heavy-oil-cracking","light-oil-cracking"}) do
      oil_effects[#oil_effects+1]={type="change-recipe-productivity",recipe=recipe,change=.1}
      force.recipes[recipe]={productivity_bonus=0}
    end
    local inputs={}
    for _,item in ipairs(vector) do inputs[#inputs+1]={name=item,amount=1} end
    force.technologies["recipe-prod-research_science_pack_productivity-1"]=
      technology("recipe-prod-research_science_pack_productivity-1",science_effects,inputs,prerequisites)
    force.technologies["recipe-prod-research_oil_cracking_productivity-1"]=
      technology("recipe-prod-research_oil_cracking_productivity-1",oil_effects,
        {{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}})
    local known={}
    for _,value in ipairs(vector) do known[value]=true end
    for _,value in ipairs(prerequisites) do known[value]=true end
    known["automation"]=true
    for value in pairs(known) do
      if force.technologies[value]==nil then force.technologies[value]=technology(value,{}, {}, {}) end
    end
    force.technologies["automation"].prerequisites={"automation-science-pack"}
    if missing then force.technologies[missing]=nil end
    for _,value in pairs(force.technologies) do value.force=force end
    function force.enable_all_prototypes() end
    function force.reset_technology_effects()
      local science=force.technologies["recipe-prod-research_science_pack_productivity-1"]
      local oil=force.technologies["recipe-prod-research_oil_cracking_productivity-1"]
      for _,recipe in ipairs(effect_names) do force.recipes[recipe].productivity_bonus=.1*(science.level-1) end
      for _,recipe in ipairs({"heavy-oil-cracking","light-oil-cracking"}) do
        force.recipes[recipe].productivity_bonus=.1*(oil.level-1)
      end
    end
    function force.add_research(value)
      if value==nil or value.enabled~=true or force.current_research~=nil then return false end
      for _,prerequisite in ipairs(value.prerequisites or {}) do
        local row=force.technologies[prerequisite]
        if row==nil or row.researched~=true then return false end
      end
      force.current_research=value;force.research_queue={value};force.research_progress=0
      return true
    end
    return force
  end
  local player=new_force("player",1)
  local game={tick=0,forces={player=player,[1]=player},surfaces={}}
  function game.create_force(name)
    local foreign=new_force(name,2);game.forces[name]=foreign;game.forces[2]=foreign;return foreign
  end
  function game.server_save(name) assert(name=="mir5-native-complete");saves=saves+1 end
  local counts={}
  local inventory={
    insert=function(stack) counts[stack.name]=(counts[stack.name] or 0)+stack.count;return stack.count end,
    get_item_count=function(name) return counts[name] or 0 end,
  }
  local lab={valid=true,energy=0,get_inventory=function(which) assert(which==1);return inventory end}
  game.surfaces[1]={create_entity=function(spec) assert(spec.name=="lab" and spec.force==player);return lab end}
  local callbacks,storage={events={}},{}
  local env={game=game,storage=storage,helpers={table_to_json=function(row) markers[#markers+1]=row;return "{}" end},
    log=function() end,script={active_mods=mods,on_init=function(fn)callbacks.init=fn end,on_load=function(fn)callbacks.load=fn end,
      on_event=function(event,fn)callbacks.events[event]=fn end},defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}}
  local cache={}
  env.require=function(name)
    assert(name=="__mir-fixture-mir5-bob-angel-f210-science-oil__/fixture_facts")
    if cache[name] then return cache[name] end
    local chunk,message=loadfile(fixture.."/fixture_facts.lua","t",env);assert(chunk,message)
    cache[name]=chunk();return cache[name]
  end
  env._G=env;setmetatable(env,{__index=_G})
  local chunk,message=loadfile(fixture.."/control.lua","t",env);assert(chunk,message);chunk()
  local ok,result=pcall(callbacks.init)
  if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  game.tick=1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  local science=player.technologies["recipe-prod-research_science_pack_productivity-1"]
  for completion=1,2 do
    science.level=science.level+1;science.researched=false;player.current_research=nil;player.research_queue={};player.reset_technology_effects()
    for _,item in ipairs(vector) do counts[item]=counts[item]-1 end
    ok,result=pcall(callbacks.events[1],{research=science});if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
    game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  end
  if tamper=="oil" then player.technologies["recipe-prod-research_oil_cracking_productivity-1"].saved_progress=.5 end
  for _=1,2 do
    ok,result=pcall(callbacks.load);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
    game.tick=game.tick+1;ok,result=pcall(callbacks.events[2]);if not ok then return {ok=false,message=tostring(result),saves=saves,markers=markers} end
  end
  local oil=player.technologies["recipe-prod-research_oil_cracking_productivity-1"]
  return {ok=true,saves=saves,markers=markers,science_level=science.level,
    oil={level=oil.level,enabled=oil.enabled,visible_when_disabled=oil.visible_when_disabled,
      saved_progress=oil.saved_progress},counts=counts}
end
''')

    def _mods(self, space_age: bool):
        profile = json.loads((ROOT / "tests" / "profiles" /
                              ("bob-angel-f210-science-oil-mir5-space-age-f210-2123.json" if space_age
                               else "bob-angel-f210-science-oil-mir5-base-f210-2123.json")).read_text())
        return {row["name"]: row["version"] for row in profile["mods"]}

    def _data(self, space_age: bool, opponent: str = ""):
        return self.lua.eval("run_data")(lua_value(self.lua, raw_case(space_age, opponent)),
                                         lua_value(self.lua, self._mods(space_age)))

    def test_profiles_extend_exact_q009_q010_closures_with_current_mir_and_own_fixture(self):
        for space_age, old_name, new_name in (
            (False, "bob-angel-full-base-f210-2123.json",
             "bob-angel-f210-science-oil-mir5-base-f210-2123.json"),
            (True, "bob-angel-full-space-age-f210-2123.json",
             "bob-angel-f210-science-oil-mir5-space-age-f210-2123.json"),
        ):
            with self.subTest(stage="space-age" if space_age else "base"):
                old = json.loads((ROOT / "tests" / "profiles" / old_name).read_text())
                new = json.loads((ROOT / "tests" / "profiles" / new_name).read_text())
                self.assertEqual((1, "mir5-bob-angel-f210-science-oil-current-successor", "f210", "2.1", "Defaults"),
                                 (new["schema"], new["kind"], new["target"], new["factorio_line"], new["settings_mode"]))
                self.assertEqual(("2.1.23", ENGINE_SHA), (new["engine"]["version"], new["engine"]["sha256"]))
                self.assertEqual(old["mods"] + [
                    {"name": "more-infinite-research", "version": "5.0.21000", "enabled": True},
                    {"name": NAME, "version": "0.1.0", "enabled": True},
                ], new["mods"])
                self.assertEqual(old["archive_sha256"] | {
                    "more-infinite-research_5.0.21000.zip": MIR_SHA,
                    FIXTURE_ARCHIVE: FIXTURE_SHA,
                }, new["archive_sha256"])
                self.assertEqual(OBSERVER_SHA, new["archive_sha256"]["mir-fixture-mir5-active-mods-observer_0.1.0.zip"])
                self.assertEqual(FIXTURE_SHA, new["archive_sha256"][FIXTURE_ARCHIVE])
                self.assertIn(SOURCE, new["scope"])
                self.assertIn(PLAYER_TREE, new["scope"])
                self.assertIn(FIXTURE_SHA, new["scope"])
                self.assertIn(f"{FIXTURE_BYTES} bytes", new["scope"])
                self.assertIn("Prepared input only", new["scope"])
                fixture_info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
                self.assertEqual(["base = 2.1.23", "more-infinite-research = 5.0.21000"],
                                 fixture_info["dependencies"][:2])
                selected = {
                    f"? {row['name']} = {row['version']}"
                    for row in new["mods"]
                    if row["name"] not in {"base", "more-infinite-research", NAME}
                }
                declared = set(fixture_info["dependencies"][2:])
                self.assertTrue(selected <= declared)
                self.assertEqual(selected | {
                    "? elevated-rails = 2.1.23", "? quality = 2.1.23",
                    "? recycler = 2.1.23", "? space-age = 2.1.23",
                }, declared)
                if space_age:
                    self.assertEqual("2.1.23", self._mods(True)["space-age"])
                    self.assertEqual(14, len(SA_VECTOR))
                else:
                    self.assertNotIn("space-age", self._mods(False))
                    self.assertEqual(8, len(BASE_VECTOR))

    def test_fixture_archive_is_a_small_owned_projection_and_does_not_include_player_source(self):
        expected = {"info.json", "fixture_facts.lua", "data-final-fixes.lua", "control.lua"}
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / f"{NAME}_0.1.0.zip"
            record = PACKAGE.build(FIXTURE, archive)
            self.assertIsNone(record["source_commit"])
            self.assertEqual(expected, {row["path"] for row in record["members"]})
            with zipfile.ZipFile(archive) as package:
                self.assertEqual({f"{NAME}_0.1.0/{name}" for name in expected},
                                 {entry.filename for entry in package.infolist() if not entry.is_dir()})
                self.assertEqual((FIXTURE / "info.json").read_bytes(),
                                 package.read(f"{NAME}_0.1.0/info.json"))
            self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest().upper(), record["sha256"].upper())

    def test_prepared_inputs_pin_the_four_raw_git_runtime_members_without_native_claims(self):
        receipt = json.loads(INPUT_RECEIPT.read_bytes())
        self.assertEqual("MIR5BobAngelF210ScienceOilPreparedInputsV1", receipt["kind"])
        self.assertEqual(INPUT_REVISION, receipt["fixture_source_commit"])
        self.assertEqual("bob-angel-f210-science-oil", receipt["case_name"])
        for field in ("native_execution", "library_mutation", "laboratory_completion", "release_qualification"):
            self.assertIs(receipt[field], False)
        self.assertIn("pending", receipt["saved_input_hashes"])
        fixture = receipt["fixture"]
        self.assertEqual((NAME, "0.1.0", FIXTURE_SHA, FIXTURE_BYTES),
                         (fixture["name"], fixture["version"], fixture["sha256"], fixture["bytes"]))
        self.assertEqual(4, len(fixture["members"]))
        self.assertEqual(4, receipt["projection_contract"]["member_count"])
        self.assertEqual(["info.json", "control.lua", "data-final-fixes.lua", "fixture_facts.lua"],
                         receipt["projection_contract"]["members"])
        self.assertIn("README", receipt["projection_contract"]["description"])
        self.assertEqual("four-member-raw-git-projection-passes-real-guard", receipt["archive_guard"]["status"])
        self.assertIn("Assert-MIRLibraryFixtureArchive", receipt["archive_guard"]["command"])
        expected = {name: f"tests/fixtures/bob-angel-f210-science-oil/{name}"
                    for name in ("info.json", "control.lua", "data-final-fixes.lua", "fixture_facts.lua")}
        self.assertEqual(expected, {row["path"]: row["source_path"] for row in fixture["members"]})
        for row in fixture["members"]:
            raw = subprocess.check_output(["git", "show", f"{INPUT_REVISION}:{row['source_path']}"], cwd=ROOT)
            self.assertEqual((row["sha256"], row["bytes"]),
                             (hashlib.sha256(raw).hexdigest().upper(), len(raw)))
        helper = receipt["package_tool"]
        raw_helper = subprocess.check_output(["git", "show", f"{INPUT_REVISION}:{helper['path']}"], cwd=ROOT)
        self.assertEqual(helper["committed_sha256"], hashlib.sha256(raw_helper).hexdigest().upper())
        expected_profiles = {
            "tests/profiles/bob-angel-f210-science-oil-mir5-base-f210-2123.json",
            "tests/profiles/bob-angel-f210-science-oil-mir5-space-age-f210-2123.json",
        }
        self.assertEqual(expected_profiles, set(receipt["profile_bindings"]))
        self.assertEqual({FIXTURE_SHA}, set(receipt["profile_bindings"].values()))
        self.assertEqual((SOURCE, PLAYER_TREE, MIR_SHA),
                         (receipt["mir_input"]["source_commit"], receipt["mir_input"]["player_tree"],
                          receipt["mir_input"]["sha256"]))
        self.assertEqual(("2.1.23", ENGINE_SHA, 679250),
                         (receipt["mir_input"]["engine"]["version"], receipt["mir_input"]["engine"]["sha256"],
                          receipt["mir_input"]["bytes"]))

    def test_data_preflight_binds_independent_vectors_before_accelerating_only_science(self):
        for space_age, vector, effect_rows in ((False, BASE_VECTOR, BASE_EFFECTS), (True, SA_VECTOR, SA_EFFECTS)):
            with self.subTest(stage="space-age" if space_age else "base"):
                result = self._data(space_age)
                self.assertTrue(result["ok"], result["message"])
                science = result["raw"]["technology"][SCIENCE]
                oil = result["raw"]["technology"][OIL]
                self.assertEqual((1, None, 1), (science["unit"]["count"], science["unit"]["count_formula"],
                                                    science["unit"]["time"]))
                self.assertEqual(("8000*2^(L-1)", 60, False),
                                 (oil["unit"]["count_formula"], oil["unit"]["time"], oil["enabled"]))
                self.assertEqual(vector, [science["unit"]["ingredients"][index][1]
                                          for index in range(1, len(vector) + 1)])
                self.assertEqual(effect_rows, [science["effects"][index]["recipe"]
                                                for index in range(1, len(effect_rows) + 1)])
        for opponent, phrase in (
            ("science-effect", "science effects differs at 1"),
            ("science-vector", "science ingredients differs at 1"),
            ("science-prerequisite", "science prerequisites differs at 1"),
            ("oil-enabled", "oil saved identity differs"),
            ("missing-producer", "science producer is absent"),
        ):
            with self.subTest(opponent=opponent):
                result = self._data(True, opponent)
                self.assertFalse(result["ok"])
                self.assertIn(phrase, result["message"])
                science = result["raw"]["technology"][SCIENCE]
                self.assertEqual(("8000*2^(L-1)", 120), (science["unit"]["count_formula"], science["unit"]["time"]))

    def test_control_registers_real_lifecycle_callbacks_without_parse_time_game_or_storage_access(self):
        result = self.lua.eval("parse_control")()
        self.assertTrue(result["ok"], result["message"] or "")
        self.assertEqual((0, 0), (result["reads"]["game"], result["reads"]["storage"]))
        callbacks = result["callbacks"]
        self.assertIsNotNone(callbacks["init"])
        self.assertIsNotNone(callbacks["load"])
        self.assertIsNotNone(callbacks["events"][1])
        self.assertIsNotNone(callbacks["events"][2])
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        on_load = source.split("script.on_load", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", on_load)
        self.assertNotIn("server_save", on_load)
        self.assertIn("value.level = level", source)
        self.assertIn("value.enabled = false", source)
        self.assertIn("force.reset_technology_effects()", source)
        self.assertIn("game.server_save(SAVE)", source)

    def test_control_declares_real_lab_two_completion_save_and_readonly_reload_contract(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        facts = (FIXTURE / "fixture_facts.lua").read_text(encoding="utf-8")
        for text in (
            'game.surfaces[1].create_entity{name="lab"',
            "defines.inventory.lab_input",
            "actual_science_laboratory_completions=state.finished",
            "if state.finished == 2 then",
            "game.server_save(SAVE)",
            "oil_seeded_not_laboratory_earned=true",
            "fixture_accelerates_science_count_and_time_only=true",
            "migration_qualification=false",
            "all_physics_qualification=false",
            "force.add_research(probe)",
        ):
            self.assertIn(text, source)
        self.assertIn("M.oil_saved_progress = .27", facts)
        self.assertIn("M.foreign_oil_saved_progress = .42", facts)
        self.assertIn("M.lab_initial = 32", facts)
        self.assertIn("M.deadline_ticks = 36000", facts)
        self.assertNotIn("__more-infinite-research__", source)
        self.assertNotIn("remote.call", source)

    def test_two_real_lab_completions_save_once_then_two_readonly_reload_readbacks(self):
        for space_age, vector, prerequisites, effect_rows in (
            (False, BASE_VECTOR, BASE_PREREQUISITES, BASE_EFFECTS),
            (True, SA_VECTOR, SA_PREREQUISITES, SA_EFFECTS),
        ):
            with self.subTest(stage="space-age" if space_age else "base"):
                result = plain(self.lua.eval("run_control_model")(
                    lua_value(self.lua, self._mods(space_age)), lua_value(self.lua, vector),
                    lua_value(self.lua, prerequisites), lua_value(self.lua, effect_rows), None))
                self.assertTrue(result["ok"], result.get("message", ""))
                self.assertEqual((1, 3), (result["saves"], result["science_level"]))
                self.assertEqual(["initial", "reload", "reload"],
                                 [row["stage"] for row in result["markers"]])
                for row in result["markers"]:
                    witness = row["witnesses"]
                    self.assertEqual(2, witness["actual_science_laboratory_completions"])
                    self.assertTrue(witness["oil_seeded_not_laboratory_earned"])
                    self.assertTrue(witness["foreign_disabled"])
                    self.assertEqual(len(effect_rows), witness["admitted_producer_count"])
                self.assertEqual(.27, result["oil"]["saved_progress"])
                self.assertTrue(all(result["counts"][name] == 30 for name in vector))
        refused = plain(self.lua.eval("run_control_model")(
            lua_value(self.lua, self._mods(True)), lua_value(self.lua, SA_VECTOR),
            lua_value(self.lua, SA_PREREQUISITES), lua_value(self.lua, SA_EFFECTS), "research-speed-5"))
        self.assertFalse(refused["ok"])
        self.assertIn("technology is absent: research-speed-5", refused["message"])
        self.assertEqual(0, refused["saves"])
        tampered = plain(self.lua.eval("run_control_model")(
            lua_value(self.lua, self._mods(False)), lua_value(self.lua, BASE_VECTOR),
            lua_value(self.lua, BASE_PREREQUISITES), lua_value(self.lua, BASE_EFFECTS), None, "oil"))
        self.assertFalse(tampered["ok"])
        self.assertIn("reload oil saved identity differs", tampered["message"])
        self.assertEqual(1, tampered["saves"])

    def test_source_guard_has_explicit_level_setter_and_readonly_opponents(self):
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertLess(source.index("value.level = level"), source.index("value.enabled = false"))
        self.assertLess(source.index("value.enabled = false"), source.index("value.saved_progress = saved"))
        self.assertIn('effect_vector(value, expected.effects, label .. " science")', source)
        self.assertIn('input_vector(value, expected.vector, label .. " science")', source)
        self.assertIn("foreign queue snapshot differs", source)
        self.assertIn("on_load_read_only=stage == \"reload\"", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", required=True, type=Path)
    args = parser.parse_args()
    LUA_RUNTIME_DIR = args.lua_runtime_dir.resolve(strict=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelScienceOilFixtureTests)
    outcome = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if outcome.wasSuccessful() else 1)
