"""Host controls for the exact official MIR 1.0.0 F200 source-save fixture."""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/migration-origins/f200-100-source"
PROFILE = ROOT / "tests/profiles/migration-origins-1.0.0-source-f200-2077.json"
DIRECT = "recipe-prod-research_gears-1"
SCIENCE = [
    ["automation-science-pack", 1],
    ["chemical-science-pack", 1],
    ["logistic-science-pack", 1],
    ["production-science-pack", 1],
]


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
    def source_technology(self):
        return {
            "name": DIRECT,
            "level": 1,
            "upgrade": True,
            "max_level": "infinite",
            "enabled": True,
            "unit": {"count_formula": "8000 * 2^(L-1)", "time": 60, "ingredients": copy.deepcopy(SCIENCE)},
            "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .10}],
        }

    def run_data(self, raw, mods):
        path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.globals().fixture_data_path = path
        self.lua.execute(r'''
          function migration_origin_run_data(raw, mods)
            local env={data={raw=raw},mods=mods}
            env._G=env;setmetatable(env,{__index=_G})
            local ok,message=pcall(function() assert(loadfile(fixture_data_path,"t",env))() end)
            return {ok=ok,message=tostring(message),raw=raw}
          end
        ''')
        return py(self.lua.eval("migration_origin_run_data")(lua(self.lua, copy.deepcopy(raw)), lua(self.lua, mods)))

    def test_data_guard_binds_original_source_identity_before_acceleration(self):
        raw = {"technology": {DIRECT: self.source_technology()}, "sentinel": {"unchanged": 17}}
        mods = {"base": "2.0.77", "more-infinite-research": "1.0.0",
                "mir-fixture-mir5-migration-origin-f200-100-source": "0.1.0"}
        accepted = self.run_data(raw, mods)
        self.assertTrue(accepted["ok"], accepted["message"])
        unit = accepted["raw"]["technology"][DIRECT]["unit"]
        self.assertEqual((1, None, 1), (unit.get("count"), unit.get("count_formula"), unit["time"]))
        self.assertEqual(SCIENCE, unit["ingredients"])
        self.assertEqual(raw["technology"][DIRECT]["effects"], accepted["raw"]["technology"][DIRECT]["effects"])
        self.assertEqual(17, accepted["raw"]["sentinel"]["unchanged"])

        wrong_science = copy.deepcopy(self.source_technology())
        wrong_science["unit"]["ingredients"][1][1] = "foreign-science-pack"
        duplicate_science = copy.deepcopy(self.source_technology())
        duplicate_science["unit"]["ingredients"][1] = duplicate_science["unit"]["ingredients"][0][:]
        variants = (
            ("closure", self.source_technology(), {**mods, "more-infinite-research": "1.0.1"}),
            ("formula", {**self.source_technology(), "unit": {"count_formula": "7999 * 2^(L-1)", "time": 60, "ingredients": copy.deepcopy(SCIENCE)}}, mods),
            ("time", {**self.source_technology(), "unit": {"count_formula": "8000 * 2^(L-1)", "time": 61, "ingredients": copy.deepcopy(SCIENCE)}}, mods),
            ("science", wrong_science, mods),
            ("duplicate-science", duplicate_science, mods),
            ("effect", {**self.source_technology(), "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .05}]}, mods),
        )
        for label, technology, candidate_mods in variants:
            with self.subTest(label=label):
                candidate = {"technology": {DIRECT: technology}, "sentinel": {"unchanged": 17}}
                before = copy.deepcopy(candidate)
                rejected = self.run_data(candidate, candidate_mods)
                self.assertFalse(rejected["ok"])
                self.assertEqual(before, rejected["raw"])

    def test_control_registers_source_callbacks_without_runtime_work_at_load(self):
        path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().fixture_control_path = path
        self.lua.execute(r'''
          function migration_origin_parse_control()
            local callbacks, forbidden={events={}},{}
            local env={
              script={active_mods={base="2.0.77",["more-infinite-research"]="1.0.0",["mir-fixture-mir5-migration-origin-f200-100-source"]="0.1.0"},
                on_init=function(fn) callbacks.init=fn end,on_load=function(fn) callbacks.load=fn end,
                on_event=function(event,fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}}
            }
            env._G=env
            setmetatable(env,{__index=function(_,key)
              if key=="game" or key=="storage" then forbidden[key]=true;return nil end
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
        # ``py`` deliberately converts contiguous positive Lua integer keys to
        # the equivalent zero-indexed Python list.  Require both actual event
        # callbacks rather than indexing it as an unconverted Lua table.
        self.assertEqual(2, len(result["callbacks"]["events"]))
        self.assertIsNotNone(result["callbacks"]["events"][0])
        self.assertIsNotNone(result["callbacks"]["events"][1])
        self.assertEqual({}, result["forbidden"])

    def test_profile_and_fixture_identity_are_source_only(self):
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
        readme = (FIXTURE / "README.md").read_text(encoding="utf-8")
        self.assertIn("not a migration pass", readme)
        self.assertIn("separately pinned MIR5 successor", readme)


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
