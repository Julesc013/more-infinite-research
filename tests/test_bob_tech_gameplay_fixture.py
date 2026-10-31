"""Host controls for the bounded F210 BobTech plus Angel gameplay fixture.

These controls run only data and runtime doubles. They preserve the independent
five-row source facts and do not replace the native lab/save/reload witness.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/bob-tech-gameplay"
PROFILE = ROOT / "tests/profiles/bob-tech-f210-2123.json"
FACTS = ROOT / "tests/fixtures/bob-tech-f210-captured-facts.json"

OFFICIAL = {
    "base": "2.1.23", "elevated-rails": "2.1.23", "quality": "2.1.23",
    "recycler": "2.1.23", "space-age": "2.1.23",
}
CONSUMPTION = {
    "automation-science-pack": 11,
    "logistic-science-pack": 8,
    "space-science-pack": 2,
}


def lua_value(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua_value(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua_value(runtime, item) for item in value])
    return value


def ordinary_rows(rows):
    return [{"type": row["type"], "name": row["name"], "amount": row["amount"]} for row in rows]


def stage_row(family, stage_name):
    stage = family[stage_name]
    finite = stage_name == "early"
    row = {
        "type": "technology", "name": stage["id"], "level": stage["level"],
        "upgrade": True, "max_level": stage["max_level"], "order": stage["order"],
        "enabled": True, "prerequisites": stage["prerequisites"],
        "unit": {
            "count_formula": stage["count_formula"], "time": stage["time"],
            "ingredients": [[name, 1] for name in stage["science"]],
        },
        "effects": [{
            "type": "change-recipe-productivity", "recipe": route["recipe"], "change": .02,
        } for route in family["routes"]],
    }
    if not finite:
        row.update(show_levels_info=False, visible_when_disabled=True)
    return row


def raw_fixture(facts):
    technology, item, recipe = {}, {}, {}
    for family in facts["families"]:
        item[family["item"]] = {"icon": family["icon"], "icon_size": family["icon_size"]}
        for route in family["routes"]:
            recipe[route["recipe"]] = {
                "enabled": False, "hidden": False, "allow_productivity": True,
                "maximum_productivity": route["maximum_productivity"],
                "ingredients": ordinary_rows(route["ingredients"]),
                "results": ordinary_rows(route["results"]),
            }
            technology[route["owner"]] = {
                "enabled": True, "prerequisites": route["owner_prerequisites"],
                "unit": {"ingredients": ordinary_rows(route["owner_science"])},
                "effects": [{"type": "unlock-recipe", "recipe": route["recipe"]}],
            }
        technology[family["early"]["id"]] = stage_row(family, "early")
        if "continuation" in family:
            technology[family["continuation"]["id"]] = stage_row(family, "continuation")
    for family in facts["families"]:
        for stage_name in ("early", "continuation"):
            for prerequisite in family.get(stage_name, {}).get("prerequisites", []):
                technology.setdefault(prerequisite, {"name": prerequisite})
    return {"item": item, "recipe": recipe, "technology": technology}


def runtime_spec(facts):
    return [{
        "key": family["key"],
        "early": family["early"]["id"],
        "tail": family.get("continuation", {}).get("id"),
        "recipes": [route["recipe"] for route in family["routes"]],
    } for family in facts["families"]]


class BobTechGameplayFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.raw = raw_fixture(cls.facts)
        cls.active = dict(OFFICIAL)
        cls.active.update(cls.facts["required_mods"])
        cls.active["mir-fixture-mir5-active-mods-observer"] = "0.1.0"
        cls.active["more-infinite-research"] = "5.0.21000"
        cls.active["mir-fixture-mir5-bob-tech-gameplay"] = "0.1.0"

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_fixture = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_fixture = (FIXTURE / "control.lua").as_posix()
        runner = (ROOT / "tools/Invoke-NativeFixture.ps1").read_text(encoding="utf-8")
        saves = re.findall(r"\$complete=Join-Path \$writeData 'saves/([^'/]+)\.zip'", runner)
        self.assertEqual(["mir5-native-complete"], saves)

    def run_data_fixture(self, raw):
        self.lua.globals().raw_fixture = lua_value(self.lua, raw)
        return self.lua.execute(r'''
            data = {raw = raw_fixture}
            return pcall(assert(loadfile(data_fixture)))
        ''')

    def test_profile_and_info_pin_the_complete_independent_f210_closure(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(("mir5-bob-tech-gameplay-native-selection", "f210", "Defaults"),
                         (profile["kind"], profile["target"], profile["settings_mode"]))
        self.assertEqual("2.1.23", profile["engine"]["version"])
        self.assertEqual("FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
                         profile["engine"]["sha256"])
        self.assertEqual(self.facts["historical_input_source_commit"],
                         profile["source_selection"]["historical_source_commit"])
        self.assertEqual(self.facts["profile_sha256"], profile["source_selection"]["sha256"])
        self.assertEqual("E0FF04FE281B39BD54AF35B3769F3E320D696E5313E4810EE28F92F72FF443B9",
                         profile["source_selection"]["settings_sha256"])
        self.assertEqual(self.active, {entry["name"]: entry["version"] for entry in profile["mods"]})
        expected_archives = {
            entry for entry in self.facts["required_mods"]
            if entry not in {"base", "space-age"}
        }
        expected_archives.add("mir-fixture-mir5-active-mods-observer")
        self.assertEqual(expected_archives, {
            name.rsplit("_", 1)[0] for name in profile["archive_sha256"]
        })
        self.assertEqual(11, len(self.facts["required_mods"]) - 2)
        self.assertEqual("tests/fixtures/bob-tech-gameplay", profile["fixture"]["root"])
        self.assertEqual(["info.json", "data-final-fixes.lua", "control.lua"],
                         profile["fixture"]["included_members"])
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-bob-tech-gameplay", "0.1.0", "2.1"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertIn("angelssmelting = 2.1.1", info["dependencies"])
        self.assertIn("more-infinite-research = 5.0.21000", info["dependencies"])

    def test_data_preflight_requires_all_five_rows_and_all_direct_owner_route_facts_before_acceleration(self):
        result = self.run_data_fixture(deepcopy(self.raw))
        self.assertTrue(result[0] if isinstance(result, tuple) else result,
                        result[1] if isinstance(result, tuple) else result)
        raw = self.lua.globals().data["raw"]
        accelerated = []
        for family in self.facts["families"]:
            for stage_name in ("early", "continuation"):
                if stage_name not in family:
                    continue
                stage = family[stage_name]
                row = raw["technology"][stage["id"]]
                accelerated.append(stage["id"])
                self.assertEqual((None, 1, 1),
                                 (row["unit"]["count_formula"], row["unit"]["count"], row["unit"]["time"]))
                self.assertEqual([route["recipe"] for route in family["routes"]],
                                 [row["effects"][index]["recipe"]
                                  for index in range(1, len(family["routes"]) + 1)])
            if family["key"] == "research_material_tin":
                self.assertIsNone(raw["technology"]["recipe-prod-research_material_tin-4"])
        self.assertEqual([
            "recipe-prod-research_material_tin-1",
            "recipe-prod-research_material_gunmetal-1",
            "recipe-prod-research_material_gunmetal-4",
            "recipe-prod-research_material_invar-1",
            "recipe-prod-research_material_invar-4",
        ], accelerated)

    def test_omitted_native_maximum_keeps_all_five_preflight_rows_and_explicit_drift_refuses(self):
        omitted = deepcopy(self.raw)
        for recipe in omitted["recipe"].values():
            del recipe["maximum_productivity"]
        result = self.run_data_fixture(omitted)
        self.assertTrue(result[0] if isinstance(result, tuple) else result)
        for family in self.facts["families"]:
            for stage_name in ("early", "continuation"):
                if stage_name in family:
                    row = self.lua.globals().data["raw"]["technology"][family[stage_name]["id"]]
                    self.assertEqual((None, 1, 1),
                                     (row["unit"]["count_formula"], row["unit"]["count"], row["unit"]["time"]))
        for maximum in (0, 2, 4, False, "3"):
            with self.subTest(maximum=maximum):
                changed = deepcopy(omitted)
                changed["recipe"]["angels-plate-invar"]["maximum_productivity"] = maximum
                result = self.run_data_fixture(changed)
                self.assertFalse(result[0] if isinstance(result, tuple) else result)
                for family in self.facts["families"]:
                    for stage_name in ("early", "continuation"):
                        if stage_name in family:
                            row = self.lua.globals().data["raw"]["technology"][family[stage_name]["id"]]
                            self.assertIsNone(row["unit"]["count"])

    def test_data_preflight_refuses_a_route_or_owner_or_effect_mismatch_without_partial_acceleration(self):
        mutations = {
            "route": lambda raw: raw["recipe"]["angels-plate-tin"].__setitem__("maximum_productivity", 2),
            "owner": lambda raw: raw["technology"]["angels-invar-smelting-1"]["prerequisites"].__setitem__(0, "wrong"),
            "effect": lambda raw: raw["technology"]["recipe-prod-research_material_gunmetal-4"]
            ["effects"].__setitem__(0, {"type": "change-recipe-productivity", "recipe": "wrong", "change": .02}),
            "prerequisite": lambda raw: raw["technology"].pop("space-science-pack"),
        }
        for name, mutate in mutations.items():
            with self.subTest(opponent=name):
                raw = deepcopy(self.raw)
                mutate(raw)
                result = self.run_data_fixture(raw)
                self.assertFalse(result[0] if isinstance(result, tuple) else result)
                actual = self.lua.globals().data["raw"]["technology"]
                for family in self.facts["families"]:
                    for stage_name in ("early", "continuation"):
                        if stage_name not in family:
                            continue
                        stage = family[stage_name]
                        row = actual[stage["id"]]
                        self.assertIsNone(row["unit"]["count"])
                        self.assertEqual(stage["count_formula"], row["unit"]["count_formula"])
                        self.assertEqual(30, row["unit"]["time"])

    def run_runtime_protocol(self, opponent):
        self.lua.globals().spec = lua_value(self.lua, runtime_spec(self.facts))
        self.lua.globals().active = lua_value(self.lua, self.active)
        self.lua.globals().opponent = opponent
        return self.lua.execute(r'''
          local callbacks, markers, saves = {events={}}, 0, 0
          local player = {valid=true,technologies={},recipes={},current_research=nil,research_queue={}}
          local external={"automation-science-pack","logistic-science-pack","space-science-pack",
            "angels-tin-smelting-1","angels-tin-casting-2","angels-gunmetal-smelting-1","angels-invar-smelting-1"}
          for _, name in ipairs(external) do player.technologies[name]={valid=true,name=name,prototype={}} end
          for _, family in ipairs(spec) do
            local function technology(name,level,researched,maximum)
              local effects={}
              for index,recipe in ipairs(family.recipes) do effects[index]={type="change-recipe-productivity",recipe=recipe,change=.02} end
              return {valid=true,name=name,force=player,level=level,researched=researched,enabled=true,
                prototype={max_level=maximum,effects=effects},research_unit_count=1,research_unit_energy=60}
            end
            player.technologies[family.early]=technology(family.early,1,false,3)
            if family.tail then player.technologies[family.tail]=technology(family.tail,4,false,4294967295) end
            for _,recipe in ipairs(family.recipes) do player.recipes[recipe]={valid=true,productivity_bonus=0} end
          end
          local remaining={}
          for _,name in ipairs({"automation-science-pack","logistic-science-pack","space-science-pack"}) do remaining[name]=0 end
          local inventory={
            get_item_count=function(name) return remaining[name] end,
            insert=function(stack) remaining[stack.name]=remaining[stack.name]+stack.count;return stack.count end,
          }
          local lab={valid=true,energy=0,get_inventory=function(index) assert(index==1);return inventory end}
          player.get_spawn_position=function() return {0,0} end
          player.add_research=function(value) player.current_research=value;return true end
          local surface={create_entity=function(row) assert(row.name=="lab" and row.force==player);return lab end}
          local environment={
            script={active_mods=active,on_init=function(callback)callbacks.init=callback end,
              on_load=function(callback)callbacks.load=callback end,on_event=function(event,callback)callbacks.events[event]=callback end},
            defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
            game={tick=2,forces={player=player},surfaces={[1]=surface},server_save=function(name)assert(name=="mir5-native-complete");saves=saves+1 end},
            storage={},helpers={table_to_json=function(value)
              assert(value.case=="bob-tech-gameplay" and value.witnesses.actual_lab_completions==11);return "{}" end},
            log=function(value)assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT "));markers=markers+1 end,
          }
          environment._G=environment
          setmetatable(environment,{__index=function(_,key)return _G[key] end})
          local loaded=pcall(assert(loadfile(control_fixture,"t",environment)))
          local init_ok,init_message=pcall(callbacks.init)
          local state=environment.storage.mir5_bob_tech_gameplay
          if not init_ok then return {loaded=loaded,init_ok=false,init_message=tostring(init_message)} end
          if opponent=="scripted" then
            assert(pcall(callbacks.events[1]))
            local first=player.current_research
            local scripted_ok,scripted_message=pcall(callbacks.events[2],{research=first,by_script=true})
            return {loaded=loaded,init_ok=true,scripted_ok=scripted_ok,scripted_message=tostring(scripted_message),
              finished=state.finished,events=state.events,next=state.next,plan=state.plan,markers=markers,saves=saves}
          end
          for index,name in ipairs(state.plan) do
            local start_ok,start_message=pcall(callbacks.events[1])
            if not start_ok then return {loaded=loaded,init_ok=true,tick_ok=false,tick_message=tostring(start_message)} end
            assert(player.current_research and player.current_research.name==name,"sequential plan changed")
            local family=nil
            for _,candidate in ipairs(spec) do if candidate.early==name or candidate.tail==name then family=candidate end end
            local value=player.current_research
            if value.name==family.early then
              local earned=0
              for prior=1,index do if state.plan[prior]==family.early then earned=earned+1 end end
              value.level=earned
              value.researched=earned==3
            else
              value.level=5
            end
            for _,recipe in ipairs(family.recipes) do player.recipes[recipe].productivity_bonus=player.recipes[recipe].productivity_bonus+.02 end
            remaining["automation-science-pack"]=remaining["automation-science-pack"]-1
            if family.key~="research_material_tin" then remaining["logistic-science-pack"]=remaining["logistic-science-pack"]-1 end
            if value.name==family.tail then remaining["space-science-pack"]=remaining["space-science-pack"]-1 end
            player.current_research=nil
            assert(pcall(callbacks.events[2],{research=value,by_script=false}))
          end
          if opponent=="bonus" then player.recipes[spec[1].recipes[1]].productivity_bonus=.04 end
          if opponent=="progress" then player.technologies[spec[2].early].level=2 end
          local finish_ok,finish_message=pcall(callbacks.events[1])
          if not finish_ok then return {loaded=loaded,init_ok=true,tick_ok=false,tick_message=tostring(finish_message),markers=markers,saves=saves,plan=state.plan} end
          local before={finished=state.finished,events=state.events,next=state.next}
          local load_ok,load_message=pcall(callbacks.load)
          local read_only=state.finished==before.finished and state.events==before.events and state.next==before.next
          local reload_ok,reload_message=pcall(callbacks.events[1])
          return {loaded=loaded,init_ok=true,tick_ok=true,load_ok=load_ok,load_message=tostring(load_message),read_only=read_only,
            reload_ok=reload_ok,reload_message=tostring(reload_message),markers=markers,saves=saves,plan=state.plan,
            finished=state.finished,events=state.events,next=state.next}
        ''')

    def test_runtime_on_init_builds_the_exact_eleven_lab_plan_and_two_reload_protocol(self):
        result = self.run_runtime_protocol("")
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["tick_ok"], result["tick_message"])
        self.assertTrue(result["load_ok"], result["load_message"])
        self.assertTrue(result["read_only"])
        self.assertTrue(result["reload_ok"], result["reload_message"])
        self.assertEqual(2, result["markers"])
        self.assertEqual(1, result["saves"])
        self.assertEqual((11, 11, 12), (result["finished"], result["events"], result["next"]))
        self.assertEqual([
            "recipe-prod-research_material_tin-1", "recipe-prod-research_material_tin-1", "recipe-prod-research_material_tin-1",
            "recipe-prod-research_material_gunmetal-1", "recipe-prod-research_material_gunmetal-1", "recipe-prod-research_material_gunmetal-1",
            "recipe-prod-research_material_gunmetal-4",
            "recipe-prod-research_material_invar-1", "recipe-prod-research_material_invar-1", "recipe-prod-research_material_invar-1",
            "recipe-prod-research_material_invar-4",
        ], [result["plan"][index] for index in range(1, 12)])

    def test_runtime_rejects_scripted_completion_and_detects_lost_completion_witnesses(self):
        result = self.run_runtime_protocol("scripted")
        self.assertTrue(result["loaded"])
        self.assertTrue(result["init_ok"])
        self.assertTrue(result["scripted_ok"], result["scripted_message"])
        self.assertEqual((0, 0, 2, 0, 0),
                         (result["finished"], result["events"], result["next"], result["markers"], result["saves"]))
        for opponent, expected in (("bonus", "native recipe productivity differs"),
                                   ("progress", "finite progression differs")):
            with self.subTest(opponent=opponent):
                result = self.run_runtime_protocol(opponent)
                self.assertTrue(result["loaded"])
                self.assertTrue(result["init_ok"])
                self.assertFalse(result["tick_ok"])
                self.assertIn(expected, result["tick_message"])
                self.assertEqual((0, 0), (result["markers"], result["saves"]))

        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("actual_lab_completions=state.finished", source)
        self.assertIn("continuation_levels_completed_by_lab=2", source)
        self.assertIn("event.by_script ~= false", source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("game.create_force", source)
        self.assertNotIn("research_queue =", source)
        self.assertNotIn("early.level =", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobTechGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
