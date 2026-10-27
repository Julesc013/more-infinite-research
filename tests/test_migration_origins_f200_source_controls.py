"""Host controls for the exact official MIR 1.0.0 F200 source-save fixture."""
import argparse
import copy
import json
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-100-source"
PROFILE = ROOT / "tests/profiles/migration-origins-1.0.0-source-f200-2077.json"
DIRECT = "recipe-prod-research_gears-1"
SECONDARY = "recipe-prod-research_plastic-1"
SCIENCE = [
    ["automation-science-pack", 1],
    ["chemical-science-pack", 1],
    ["logistic-science-pack", 1],
    ["production-science-pack", 1],
]
SETTING = "ips-enable-research_breeding"
CATALOGUE_MODULE = "__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue"


def py(value):
    if hasattr(value, "items"):
        items = list(value.items())
        keys = [key for key, _ in items]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in items}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        return runtime.table_from({key: lua(runtime, item) for key, item in value.items()})
    if isinstance(value, list):
        return runtime.table_from([lua(runtime, item) for item in value])
    return value


class MigrationOriginF200SourceControls(unittest.TestCase):
    def source_technology(self, name, recipe):
        return {
            "type": "technology", "name": name, "level": 1, "upgrade": True,
            "max_level": "infinite", "enabled": True,
            "unit": {"count_formula": "8000 * 2^(L-1)", "time": 60,
                     "ingredients": copy.deepcopy(SCIENCE)},
            "effects": [{"type": "change-recipe-productivity", "recipe": recipe, "change": .10}],
        }

    def source_raw(self):
        return {"technology": {
            DIRECT: self.source_technology(DIRECT, "iron-gear-wheel"),
            SECONDARY: self.source_technology(SECONDARY, "plastic-bar"),
        }, "sentinel": {"unchanged": 17}}

    def run_data(self, raw, mods, breeding=False):
        path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().fixture_data_path = path
        self.lua.execute(r'''
          function migration_origin_run_data(raw, mods, breeding)
            local catalogue={technology_prefix="recipe-prod-research_",technology_suffix="-1",maximum_rows=31,
              minimum_rows=2,direct="recipe-prod-research_gears-1",unavailable_space_age_setting="ips-enable-research_breeding",
              source_formula="8000 * 2^(L-1)",source_time=60,
              source_science={["automation-science-pack"]=1,["chemical-science-pack"]=1,
                ["logistic-science-pack"]=1,["production-science-pack"]=1}}
            local env={data={raw=raw},mods=mods,settings={startup={
              ["ips-enable-research_breeding"]={value=breeding}}}}
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return catalogue end
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_run_data")(
            lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods), breeding))

    def test_data_guard_records_only_original_source_roster_before_acceleration(self):
        mods = {"base": "2.0.77", "more-infinite-research": "1.0.0",
                "mir-fixture-mir5-migration-origin-f200-100-source": "0.1.0"}
        accepted = self.run_data(self.source_raw(), mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        direct = accepted["raw"]["technology"][DIRECT]["unit"]
        secondary = accepted["raw"]["technology"][SECONDARY]["unit"]
        self.assertEqual((1, None, 1), (direct.get("count"), direct.get("count_formula"), direct["time"]))
        self.assertEqual((None, "8000 * 2^(L-1)", 60),
                         (secondary.get("count"), secondary.get("count_formula"), secondary["time"]))
        self.assertEqual(SCIENCE, accepted["raw"]["technology"][DIRECT]["unit"]["ingredients"])
        self.assertEqual(17, accepted["raw"]["sentinel"]["unchanged"])

        wrong_science = self.source_raw()
        wrong_science["technology"][SECONDARY]["unit"]["ingredients"][1][0] = "foreign-science-pack"
        duplicate_science = self.source_raw()
        duplicate_science["technology"][SECONDARY]["unit"]["ingredients"][1] = \
            duplicate_science["technology"][SECONDARY]["unit"]["ingredients"][0][:]
        wrong_effect = self.source_raw()
        wrong_effect["technology"][DIRECT]["effects"][0]["change"] = .05
        variants = (
            ("closure", self.source_raw(), {**mods, "more-infinite-research": "1.0.1"}, False),
            ("setting", self.source_raw(), mods, True),
            ("formula", {"technology": {DIRECT: {**self.source_technology(DIRECT, "iron-gear-wheel"),
                                                     "unit": {"count_formula": "7999 * 2^(L-1)", "time": 60,
                                                              "ingredients": copy.deepcopy(SCIENCE)}},
                                      SECONDARY: self.source_technology(SECONDARY, "plastic-bar")}}, mods, False),
            ("science", wrong_science, mods, False),
            ("duplicate-science", duplicate_science, mods, False),
            ("gear-effect", wrong_effect, mods, False),
        )
        for label, candidate, candidate_mods, breeding in variants:
            with self.subTest(label=label):
                before = copy.deepcopy(candidate)
                rejected = self.run_data(candidate, candidate_mods, breeding)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, rejected["raw"])

    def test_data_guard_refuses_an_unbounded_source_prefix_roster_before_writes(self):
        mods = {"base": "2.0.77", "more-infinite-research": "1.0.0",
                "mir-fixture-mir5-migration-origin-f200-100-source": "0.1.0"}
        raw = self.source_raw()
        for index in range(30):
            name = f"recipe-prod-research_extra_{index}-1"
            raw["technology"][name] = self.source_technology(name, f"extra-recipe-{index}")
        before = copy.deepcopy(raw)
        rejected = self.run_data(raw, mods)
        self.assertFalse(rejected["ok"])
        self.assertEqual(before, rejected["raw"])

    def test_settings_update_makes_only_the_unavailable_source_setting_nondefault(self):
        path = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.globals().fixture_settings_path = path
        self.lua.execute(r'''
          function migration_origin_run_settings()
            local setting={type="bool-setting",name="ips-enable-research_breeding",setting_type="startup",default_value=true}
            local env={data={raw={["bool-setting"]={ ["ips-enable-research_breeding"]=setting }}},
              mods={base="2.0.77",["more-infinite-research"]="1.0.0",
                ["mir-fixture-mir5-migration-origin-f200-100-source"]="0.1.0"}}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_settings_path,"t",env))() end)
            return {ok=ok,message=tostring(message),setting=setting}
          end
        ''')
        result = py(self.lua.eval("migration_origin_run_settings")())
        self.assertTrue(result["ok"], result["message"])
        self.assertFalse(result["setting"]["default_value"])

    def test_control_registers_bounded_source_callbacks_without_runtime_work_at_load(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().fixture_control_path = path
        self.lua.execute(r'''
          function migration_origin_parse_control()
            local callbacks, forbidden={events={}},{ }
            local catalogue={technology_prefix="recipe-prod-research_",technology_suffix="-1",maximum_rows=31,
              minimum_rows=2,direct="recipe-prod-research_gears-1",unavailable_space_age_setting="ips-enable-research_breeding"}
            local env={
              script={active_mods={base="2.0.77",["more-infinite-research"]="1.0.0",
                ["mir-fixture-mir5-migration-origin-f200-100-source"]="0.1.0"},
                on_init=function(fn) callbacks.init=fn end,on_load=function(fn) callbacks.load=fn end,
                on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
            }
            env.require=function(name) assert(name=="__mir-fixture-mir5-migration-origin-f200-100-source__/catalogue");return catalogue end
            env._G=env
            setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" or key=="settings" then forbidden[key]=true;return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(fixture_control_path,"t",env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        result = py(self.lua.eval("migration_origin_parse_control")())
        self.assertTrue(result["ok"], result["message"])
        self.assertIsNotNone(result["callbacks"]["init"])
        self.assertIsNotNone(result["callbacks"]["load"])
        self.assertEqual(2, len(result["callbacks"]["events"]))
        self.assertIsNotNone(result["callbacks"]["events"][0])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertEqual({}, result["forbidden"])

    def test_profile_and_fixture_identity_bind_source_only_inputs_and_runtime_members(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(("mir-fixture-mir5-migration-origin-f200-100-source", "0.1.0", "2.0"),
                         (info["name"], info["version"], info["factorio_version"]))
        self.assertEqual(("1.0.0", "f0057a96847512b50acdd6e23fc21b5b41e75adb", "f200", "2.0.77",
                          "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B"),
                         (profile["origin_tag"], profile["origin_source_commit"], profile["target"],
                          profile["engine"]["version"], profile["engine"]["sha256"]))
        self.assertEqual({"base": "2.0.77", "more-infinite-research": "1.0.0",
                          "mir-fixture-mir5-migration-origin-f200-100-source": "0.1.0"},
                         {row["name"]: row["version"] for row in profile["mods"]})
        self.assertEqual("C328D8F958BEC2A44297E94E83B1A956D76BEA5E333601A42FDDE60F4155472F",
                         profile["archive_sha256"]["more-infinite-research_1.0.0.zip"])
        self.assertEqual({"README.md", "catalogue.lua", "control.lua", "data-final-fixes.lua", "info.json", "settings-updates.lua"},
                         {path.name for path in FIXTURE.iterdir() if path.is_file()})
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("source_roster", control)
        self.assertIn("foreign_queue_progress", control)
        self.assertIn("detached_progress", control)
        self.assertIn("manual_mining_speed_modifier", control)
        self.assertLess(control.index("force.reset_technology_effects()"), control.index("foreign.research_queue"))
        foreign = control.index("local function establish_foreign_state")
        queue = control.index("foreign.research_queue", foreign)
        self.assertLess(control.index("prerequisites(direct)", foreign), queue)
        self.assertLess(control.index("prerequisites(probe)", foreign), queue)
        self.assertNotRegex(control, re.compile(r"\.level\s*=.*?\n.*?\.researched\s*=\s*false", re.DOTALL))
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn("not a migration pass", readme)
        self.assertIn("separately pinned MIR5 successor", readme)
        self.assertIn("setting readback", readme)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    MigrationOriginF200SourceControls.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(MigrationOriginF200SourceControls))
    sys.exit(0 if result.wasSuccessful() else 1)
