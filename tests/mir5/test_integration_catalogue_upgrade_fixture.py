import argparse
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/integration-catalogue-upgrade"
RECOVERED = ROOT / "tests/mir5/fixtures/armor-py-f200-472-recovered-facts.json"
BASE_ORACLE = ROOT / "spec/mir5/inventory/modern-f200-470.json"
CONTINUATIONS = ROOT / "tests/mir5/fixtures/native-modded-continuations-f200-captured-facts.json"
F200_RUNTIME_API = Path("D:/Programs/Factorio/2.0/doc-html/runtime-api.json")


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [py(value[key]) for key in range(1, max(keys) + 1)]
        return {key: py(value[key]) for key in keys}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        out = runtime.table()
        for key, item in value.items():
            out[key] = lua(runtime, item)
        return out
    if isinstance(value, list):
        out = runtime.table()
        for index, item in enumerate(value, 1):
            out[index] = lua(runtime, item)
        return out
    return value


def merge_row(base, patch):
    value = copy.deepcopy(base)
    for key, item in patch.items():
        if isinstance(item, dict) and isinstance(value.get(key), dict):
            value[key] = merge_row(value[key], item)
        else:
            value[key] = copy.deepcopy(item)
    return value


class IntegrationCatalogueUpgradeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recovered = {row["id"]: row for row in json.loads(RECOVERED.read_text(encoding="utf-8"))["profiles"]}
        cls.base = next(row for row in json.loads(BASE_ORACLE.read_text(encoding="utf-8"))["profiles"] if row["id"] == "base-f200")
        cls.continuations = json.loads(CONTINUATIONS.read_text(encoding="utf-8"))

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((FIXTURE / "catalogue.lua").as_posix()))

    def _expected_public(self, identifier):
        base = {row["name"] for row in self.base["technology_owner_progression_facts"]}
        base -= {
            "recipe-prod-research_oil_cracking_productivity-1",
            "recipe-prod-research_oil_processing_productivity-1",
        } if identifier.startswith("py-") else set()
        extras = {
            "armor-bobwarfare": {"recipe-prod-research_armor_components-1"},
            "py-coal": {"recipe-prod-research_material_py_log-1", "recipe-prod-research_material_py_log-4"},
            "py-alienlife-hightech": {
                "recipe-prod-research_breeding-1", "recipe-prod-research_supercapacitor-1",
                "recipe-prod-research_superconductor-1",
            },
        }[identifier]
        return base | extras

    def _expected_preflight(self, identifier):
        recovered = self.recovered[identifier]
        rows = {}
        for values in recovered["named_rows"].values():
            for row in values:
                rows[row["name"]] = row
        common = self.continuations["common_published_rows"]["laser-shooting-speed-8"]
        profile = next(row for row in self.continuations["profiles"] if row["id"] == identifier)
        patch = profile["published_field_changes"].get("laser-shooting-speed-8", {})
        rows["laser-shooting-speed-8"] = merge_row(common, patch)
        return rows

    def _run_data(self, stage, raw, mods):
        self.lua.globals().stage_path = (FIXTURE / stage / "data-final-fixes.lua").as_posix()
        self.lua.globals().common_path = (FIXTURE / "data-final-common.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function run_integration_data(raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue_path, "t", env))()
              end
              if name == "__mir-fixture-mir5-integration-catalogue-upgrade__/data-final-common" then
                return assert(loadfile(common_path, "t", env))()
              end
              error("unexpected fixture require: " .. tostring(name))
            end
            env._G = env
            setmetatable(env, {__index=function(_, key) return _G[key] end})
            local ok, message = pcall(function() assert(loadfile(stage_path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        ''')
        return self.lua.eval("run_integration_data")(lua(self.lua, raw), lua(self.lua, mods))

    def test_compact_public_rows_are_exactly_recovered_not_candidate_derived(self):
        expected_counts = {"armor-bobwarfare": 55, "py-coal": 54, "py-alienlife-hightech": 55}
        for identifier, expected_count in expected_counts.items():
            with self.subTest(profile=identifier):
                profile = self.plan["profiles"][identifier]
                self.assertEqual(self._expected_public(identifier), set(profile["public"]))
                self.assertEqual(expected_count, len(profile["public"]))
                self.assertEqual("laser-shooting-speed-8", profile["continuation"])
                self.assertIn(profile["primary"], profile["public"])
                self.assertIn(profile["continuation"], profile["public"])

    def test_preflight_rows_match_independent_published_facts(self):
        for identifier in self.plan["profiles"]:
            with self.subTest(profile=identifier):
                expected = self._expected_preflight(identifier)
                profile = self.plan["profiles"][identifier]
                self.assertEqual(set(expected), set(profile["preflight_names"]))
                self.assertEqual(expected, profile["preflight"])

    def test_finite_py_log_is_explicitly_early_three_then_tail_four(self):
        coal = self.plan["profiles"]["py-coal"]
        self.assertEqual({
            "early": "recipe-prod-research_material_py_log-1", "tail": "recipe-prod-research_material_py_log-4",
            "early_level": 3, "tail_level": 5,
        }, coal["finite"])
        self.assertEqual(3, coal["preflight"][coal["finite"]["early"]]["max_level"])
        self.assertEqual(50_000_000, coal["preflight"][coal["finite"]["tail"]]["max_level"])
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn("value.level, value.researched = finite.early_level, true", control)
        self.assertIn("value.level, value.researched = finite.tail_level, false", control)
        self.assertNotIn("finite.tail_level, true", control)

    def test_data_preflight_accelerates_only_the_two_real_lab_rows(self):
        for identifier, profile in self.plan["profiles"].items():
            raw = {"technology": copy.deepcopy(profile["preflight"]), "untouched": {"flag": 19}}
            for stage, mir, fixture in (("published-4.7", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
                mods = {"base": "2.0.77", "more-infinite-research": mir,
                        "mir-fixture-mir5-integration-catalogue-upgrade": fixture}
                mods.update(profile["requires"])
                with self.subTest(profile=identifier, stage=stage):
                    result = self._run_data(stage, copy.deepcopy(raw), mods)
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])
                    for name in profile["preflight_names"]:
                        unit = actual["technology"][name]["unit"]
                        if name in (profile["primary"], profile["continuation"]):
                            self.assertEqual((None, "1", 1), (unit.get("count"), unit["count_formula"], unit["time"]))
                        else:
                            expected = profile["preflight"][name]["unit"]
                            self.assertEqual(expected, unit)
                    self.assertEqual(19, actual["untouched"]["flag"])

    def test_data_preflight_rejects_named_effect_or_profile_drift_before_mutation(self):
        for identifier, profile in self.plan["profiles"].items():
            raw = {"technology": copy.deepcopy(profile["preflight"])}
            bad_effect = copy.deepcopy(raw)
            bad_effect["technology"][profile["primary"]]["effects"][0]["change"] = 0.03
            mods = {"base": "2.0.77", "more-infinite-research": "4.7.20002",
                    "mir-fixture-mir5-integration-catalogue-upgrade": "0.1.0"}
            mods.update(profile["requires"])
            with self.subTest(profile=identifier, opponent="effect"):
                result = self._run_data("published-4.7", bad_effect, mods)
                self.assertFalse(result["ok"])
                self.assertIn("published row differs before acceleration", result["message"])
                self.assertEqual(profile["preflight"][profile["primary"]]["unit"], py(result["raw"])["technology"][profile["primary"]]["unit"])
            with self.subTest(profile=identifier, opponent="closure"):
                missing = dict(mods)
                missing.pop(next(iter(profile["requires"])))
                result = self._run_data("published-4.7", copy.deepcopy(raw), missing)
                self.assertFalse(result["ok"])
                self.assertRegex(result["message"], r"(profile closure differs|no admitted integration profile)")

    def test_control_registers_without_game_or_storage_access_and_keeps_native_boundaries(self):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.globals().catalogue_path = (FIXTURE / "catalogue.lua").as_posix()
        self.lua.execute(r'''
          function parse_integration_control(source)
            local callbacks, forbidden = {events={}}, {}
            local active = {base="2.0.77", ["more-infinite-research"]=source and "4.7.20002" or "5.0.20000",
              ["mir-fixture-mir5-integration-catalogue-upgrade"]=source and "0.1.0" or "0.2.0",
              boblibrary="2.1.0", bobwarfare="2.1.0"}
            local env = {
              require=function(name)
                assert(name == "__mir-fixture-mir5-integration-catalogue-upgrade__/catalogue")
                return assert(loadfile(catalogue_path, "t", _G))()
              end,
              script={active_mods=active, on_init=function(fn) callbacks.init=fn end,
                on_load=function(fn) callbacks.load=fn end, on_configuration_changed=function(fn) callbacks.configuration=fn end,
                on_event=function(event, fn) callbacks.events[event]=fn end},
              defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
            }
            env._G=env
            setmetatable(env,{__index=function(_, key)
              if key == "game" or key == "storage" then forbidden[key]=true; return nil end
              return _G[key]
            end})
            local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
            return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
          end
        ''')
        for source in (True, False):
            with self.subTest(source=source):
                result = self.lua.eval("parse_integration_control")(source)
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                self.assertIsNotNone(result["callbacks"]["init"] if source else result["callbacks"]["configuration"])

    def test_fixture_never_writes_effects_or_uses_a_generic_research_solver(self):
        text = "\n".join(path.read_text(encoding="utf-8") for path in FIXTURE.rglob("*.lua"))
        self.assertIn('local SAVE = "mir5-native-complete"', text)
        self.assertIn("queued_progress=.42", text)
        self.assertIn("paused_progress=.27", text)
        self.assertIn("foreign_disablement_checked=true", text)
        self.assertIn("script.on_load(function()", text)
        self.assertNotIn("productivity_bonus =", text)
        self.assertNotIn("research_queue_enabled", text)
        self.assertNotIn("enable_all_prototypes() end", text)
        self.assertNotIn("game.technology_prototypes", text)
        self.assertNotIn("prototypes.technology", text)
        self.assertNotIn("require(\"research.", text)
        self.assertNotIn("__more-infinite-research__", text)

    def test_documented_force_fields_exist_in_exact_f200_api_when_installed(self):
        if not F200_RUNTIME_API.is_file():
            self.skipTest("F200 runtime API documentation is not installed")
        document = json.loads(F200_RUNTIME_API.read_text(encoding="utf-8"))
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"] for row in lua_force["attributes"]}
        self.assertTrue(set(self.plan["force_fields"]) <= fields)
        self.assertNotIn("research_queue_enabled", fields)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(IntegrationCatalogueUpgradeFixtureTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
