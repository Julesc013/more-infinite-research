"""Host controls for the private F210 Bob-core material laboratory witness.

These controls only execute the fixture against small data/runtime doubles. They
never launch Factorio, claim native completion, or replace the required current
candidate full-catalogue comparison.
"""
import argparse
from copy import deepcopy
import json
import re
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/bob-core-gameplay"
PROFILE = ROOT / "tests/mir5/profiles/bob-core-gameplay-f210-2123.json"
BASE_PROFILE = ROOT / "tests/mir5/profiles/bob-core-f210-2123.json"
FACTS = ROOT / "tests/mir5/fixtures/bob-core-f210-captured-facts.json"
INITIAL_PACKS = 64
CONSUMPTION = {
    "automation-science-pack": 28,
    "logistic-science-pack": 20,
    "chemical-science-pack": 16,
    "production-science-pack": 8,
    "space-science-pack": 10,
    "metallurgic-science-pack": 4,
}


def lua_value(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua_value(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua_value(runtime, item) for item in value])
    return value


def row_value(family, stage_name):
    stage = family[stage_name]
    finite = stage_name == "early"
    value = {
        "type": "technology",
        "name": stage["id"],
        "level": stage["level"],
        "upgrade": True,
        "max_level": stage["max_level"],
        "order": stage["order"],
        "enabled": True,
        "prerequisites": stage["prerequisites"],
        "effects": [{
            "type": "change-recipe-productivity",
            "recipe": route["recipe"],
            "change": 0.02,
        } for route in family["routes"]],
        "unit": {
            "count_formula": stage["count_formula"],
            "time": stage["time"],
            "ingredients": [[name, 1] for name in stage["science"]],
        },
    }
    if not finite:
        value["show_levels_info"] = False
        value["visible_when_disabled"] = True
    return value


def fixture_rows(facts):
    return {
        family[stage_name]["id"]: row_value(family, stage_name)
        for family in facts["families"]
        for stage_name in ("early", "continuation")
    }


def fixture_spec(facts):
    return [{
        "key": family["key"],
        "early": family["early"]["id"],
        "tail": family["continuation"]["id"],
        "recipes": [route["recipe"] for route in family["routes"]],
    } for family in facts["families"]]


class BobCoreGameplayFixtureTests(unittest.TestCase):
    def test_completed_save_name_matches_the_native_runner_endpoint(self):
        runner = (ROOT / "tools/mir5/Invoke-NativeFixture.ps1").read_text(encoding="utf-8")
        names = re.findall(r"\$complete\s*=\s*Join-Path\s+\$writeData\s+'saves/([^/']+)\.zip'", runner)
        self.assertEqual(1, len(names))
        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local SAVE = "' + names[0] + '"', source)

    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.expected_ids = [
            family[stage]["id"]
            for family in cls.facts["families"]
            for stage in ("early", "continuation")
        ]

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().data_fixture = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().control_fixture = (FIXTURE / "control.lua").as_posix()

    def run_data_fixture(self, rows):
        self.lua.globals().fixture_rows = lua_value(self.lua, rows)
        return self.lua.execute(r'''
          data = {raw = {technology = fixture_rows}}
          return pcall(assert(loadfile(data_fixture)))
        ''')

    def test_profile_and_fixture_pin_the_exact_no_angel_closure(self):
        base = json.loads(BASE_PROFILE.read_text(encoding="utf-8"))
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(base["engine"], profile["engine"])
        self.assertEqual(base["archive_sha256"], profile["archive_sha256"])
        self.assertEqual(base["source_selection"], profile["source_selection"])
        self.assertEqual(base["mods"] + [
            {"name": "more-infinite-research", "version": "5.0.21000", "enabled": True},
            {"name": "mir-fixture-mir5-bob-core-gameplay", "version": "0.1.0", "enabled": True},
        ], profile["mods"])
        self.assertEqual("mir5-bob-core-gameplay-native-selection", profile["kind"])
        self.assertIn("full-catalogue capture/comparison remains required", profile["scope"])
        self.assertNotIn("angelssmelting", {entry["name"] for entry in profile["mods"]})

        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-bob-core-gameplay", "0.1.0", "2.1"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual([
            "base = 2.1.23", "space-age = 2.1.23", "boblibrary = 3.0.1",
            "bobores = 3.0.0", "bobplates = 3.0.2", "bobelectronics = 3.0.1",
            "bobtech = 3.0.0", "more-infinite-research = 5.0.21000",
        ], info["dependencies"])

    def test_data_preflight_matches_all_fourteen_independent_rows_then_changes_only_cost_and_time(self):
        rows = fixture_rows(self.facts)
        result = self.run_data_fixture(rows)
        self.assertTrue(result[0] if isinstance(result, tuple) else result,
                        result[1] if isinstance(result, tuple) else result)
        actual = self.lua.globals().data["raw"]["technology"]
        self.assertEqual(self.expected_ids, list(rows))
        for family in self.facts["families"]:
            for stage_name in ("early", "continuation"):
                with self.subTest(family=family["key"], stage=stage_name):
                    stage = family[stage_name]
                    row = actual[stage["id"]]
                    self.assertEqual((stage["id"], stage["order"], stage["level"], stage["max_level"]),
                                     (row["name"], row["order"], row["level"], row["max_level"]))
                    self.assertEqual(stage["prerequisites"], [row["prerequisites"][index]
                                                                for index in range(1, len(stage["prerequisites"]) + 1)])
                    self.assertEqual(stage["science"], [row["unit"]["ingredients"][index][1]
                                                         for index in range(1, len(stage["science"]) + 1)])
                    self.assertEqual([route["recipe"] for route in family["routes"]],
                                     [row["effects"][index]["recipe"]
                                      for index in range(1, len(family["routes"]) + 1)])
                    self.assertEqual((None, 1, 1), (row["unit"]["count_formula"],
                                                    row["unit"]["count"], row["unit"]["time"]))
                    if stage_name == "early":
                        self.assertIsNone(row["show_levels_info"])
                        self.assertIsNone(row["visible_when_disabled"])
                    else:
                        self.assertEqual((False, True), (row["show_levels_info"], row["visible_when_disabled"]))

    def test_data_preflight_refuses_late_science_effect_or_continuation_boundary_drift_without_partial_acceleration(self):
        mutations = {
            "science": lambda rows: rows["recipe-prod-research_material_copper_tungsten-4"]
            ["unit"]["ingredients"].__setitem__(5, ["wrong-science", 1]),
            "effect": lambda rows: rows["recipe-prod-research_material_lead-1"]
            ["effects"].__setitem__(0, {"type": "change-recipe-productivity", "recipe": "bob-lead-plate", "change": 0.03}),
            "boundary": lambda rows: rows["recipe-prod-research_material_tin-4"].__setitem__("max_level", 3),
        }
        for name, mutate in mutations.items():
            with self.subTest(mutation=name):
                rows = fixture_rows(self.facts)
                mutate(rows)
                result = self.run_data_fixture(rows)
                self.assertFalse(result[0])
                for family in self.facts["families"]:
                    for stage_name in ("early", "continuation"):
                        row = self.lua.globals().data["raw"]["technology"][family[stage_name]["id"]]
                        self.assertIsNone(row["unit"]["count"])
                        self.assertEqual(family[stage_name]["count_formula"], row["unit"]["count_formula"])
                        self.assertEqual(30, row["unit"]["time"])

    def test_control_registration_and_saved_native_witness_are_read_only_and_reject_lost_earned_state(self):
        self.lua.globals().spec = lua_value(self.lua, fixture_spec(self.facts))
        result = self.lua.execute(r'''
          local callbacks, reads = {events={}}, {}
          local environment = {
            script = {
              active_mods = {},
              on_init=function(callback) callbacks.init=callback end,
              on_load=function(callback) callbacks.load=callback end,
              on_event=function(event, callback) callbacks.events[event]=callback end,
            },
            defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
          }
          environment._G = environment
          setmetatable(environment, {__index=function(_, key)
            if key == "game" or key == "storage" then reads[key] = (reads[key] or 0) + 1 end
            return _G[key]
          end})
          local chunk = assert(loadfile(control_fixture, "t", environment))
          local ok, message = pcall(chunk)
          return {ok=ok,message=tostring(message),callbacks=callbacks,reads=reads}
        ''')
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNone(result["reads"]["game"])
        self.assertIsNone(result["reads"]["storage"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertIsNotNone(result["callbacks"]["events"][2])

        self.lua.globals().consumption = lua_value(self.lua, CONSUMPTION)
        for opponent, expected in (("", ""), ("lost-earned", "earned finite-three/tail-four"),
                                   ("lost-bonus", "native recipe productivity differs"),
                                   ("science", "science consumption differs"),
                                   ("lost-tail", "earned finite-three/tail-four")):
            with self.subTest(opponent=opponent):
                self.lua.globals().opponent = opponent
                result = self.lua.execute(r'''
                  local callbacks, markers = {events={}}, 0
                  local active = {
                    base="2.1.23", ["space-age"]="2.1.23", boblibrary="3.0.1", bobores="3.0.0",
                    bobplates="3.0.2", bobelectronics="3.0.1", bobtech="3.0.0",
                    ["more-infinite-research"]="5.0.21000",
                    ["mir-fixture-mir5-bob-core-gameplay"]="0.1.0",
                  }
                  local player = {valid=true, technologies={}, recipes={}, current_research=nil, research_queue={}}
                  for _, family in ipairs(spec) do
                    local function technology(name, level, researched, maximum)
                      local effects = {}
                      for index, recipe in ipairs(family.recipes) do
                        effects[index] = {type="change-recipe-productivity", recipe=recipe, change=.02}
                        player.recipes[recipe] = {productivity_bonus=.08}
                      end
                      return {valid=true,name=name,level=level,researched=researched,enabled=true,
                        visible_when_disabled=false,prototype={max_level=maximum,effects=effects}}
                    end
                    player.technologies[family.early] = technology(family.early, 3, true, 3)
                    player.technologies[family.tail] = technology(family.tail, 5, false, 4294967295)
                  end
                  local remaining = {}
                  for name, count in pairs(consumption) do remaining[name] = 64 - count end
                  local inventory = {get_item_count=function(name) return remaining[name] end}
                  local lab = {valid=true,get_inventory=function(index)
                    assert(index == 1, "unexpected inventory")
                    return inventory
                  end}
                  local plan = {}
                  for _, family in ipairs(spec) do
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.early
                    plan[#plan+1] = family.tail
                  end
                  local state = {phase="complete",plan=plan,next=29,finished=28,events=28,lab=lab,deadline=36000}
                  local environment = {
                    script={active_mods=active,on_init=function(callback) callbacks.init=callback end,
                      on_load=function(callback) callbacks.load=callback end,
                      on_event=function(event, callback) callbacks.events[event]=callback end},
                    defines={events={on_tick=1,on_research_finished=2},inventory={lab_input=1}},
                    game={tick=2,forces={player=player}}, storage={mir5_bob_core_gameplay=state},
                    helpers={table_to_json=function(value)
                      assert(value.case == "bob-core-gameplay" and value.stage == "reload"
                        and value.witnesses.actual_lab_completions == 28)
                      return "{}"
                    end},
                    log=function(value) assert(value:match("^%[MIR5_NATIVE_FIXTURE%] RESULT ")); markers=markers+1 end,
                  }
                  environment._G = environment
                  setmetatable(environment,{__index=function(_, key) return _G[key] end})
                  local chunk = assert(loadfile(control_fixture, "t", environment))
                  assert(pcall(chunk))
                  local saved = {phase=state.phase,next=state.next,finished=state.finished,events=state.events}
                  local load_ok, load_message = pcall(callbacks.load)
                  local read_only = state.phase == saved.phase and state.next == saved.next
                    and state.finished == saved.finished and state.events == saved.events
                  if opponent == "lost-earned" then player.technologies[spec[1].early].level = 2 end
                  if opponent == "lost-bonus" then player.recipes[spec[2].recipes[1]].productivity_bonus = .06 end
                  if opponent == "science" then remaining["metallurgic-science-pack"] = remaining["metallurgic-science-pack"] + 1 end
                  if opponent == "lost-tail" then player.technologies[spec[3].tail].level = 4 end
                  local tick_ok, tick_message = pcall(callbacks.events[1])
                  return {load_ok=load_ok,load_message=tostring(load_message),read_only=read_only,
                    tick_ok=tick_ok,tick_message=tostring(tick_message),markers=markers}
                ''')
                self.assertTrue(result["load_ok"], result["load_message"])
                self.assertTrue(result["read_only"])
                if opponent:
                    self.assertFalse(result["tick_ok"])
                    self.assertIn(expected, result["tick_message"])
                    self.assertEqual(0, result["markers"])
                else:
                    self.assertTrue(result["tick_ok"], result["tick_message"])
                    self.assertEqual(1, result["markers"])

        source = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("on_research_finished", source)
        self.assertIn("actual_lab_completions=state.finished", source)
        self.assertIn("candidate_full_catalogue_comparison_required=true", source)
        self.assertNotIn("research_recursive", source)
        self.assertNotIn("enable_all_prototypes", source)
        self.assertNotIn("game.create_force", source)
        self.assertNotIn("force.research_queue =", source)
        self.assertNotIn("early.level =", source)
        self.assertNotIn("tail.level =", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobCoreGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
