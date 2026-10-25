import argparse
import json
import os
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/full-catalogue-upgrade"
F210 = FIXTURE / "f210"
SHARED = FIXTURE / "shared"
PROFILES = ROOT / "tests/profiles"
ORACLE = ROOT / "spec/inventory/modern-f210-470.json"
F210_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F210_RUNTIME_API"),
    "D:/Games/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "D:/Games/Factorio/2.1/doc-html/runtime-api.json",
    "D:/Programs/Factorio/2.1/doc-html/runtime-api.json",
)
OBSERVER = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
PUBLISHED = "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F"
CANDIDATE = "C8E0C570213F41CA8C816A29D1556FD40A36896D31ED56B07856652B2DE7F32A"
OWNERS = {
    "low-density-structure-productivity",
    "plastic-bar-productivity",
    "processing-unit-productivity",
    "rocket-fuel-productivity",
    "steel-plate-productivity",
}
DESCRIPTORS = (
    ("research_copper", "recipe-prod-research_copper-1", "copper-plate"),
    ("research_iron", "recipe-prod-research_iron-1", "iron-plate"),
    ("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"),
    ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"),
    ("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"),
    ("research_grenades", "recipe-prod-research_grenades-1", "grenade"),
    ("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"),
    ("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"),
    ("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"),
    ("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"),
)


def f210_runtime_api_path():
    for candidate in F210_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


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


class FullCatalogueUpgradeF210FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.oracle = {row["id"]: row for row in json.loads(ORACLE.read_text(encoding="utf-8"))["profiles"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((SHARED / "f210-catalogue.lua").as_posix()))

    def expected(self, name):
        facts = self.oracle[name]["technology_owner_progression_facts"]
        return (
            {fact["name"] for fact in facts},
            {fact["name"] for fact in facts if fact["group"] != "scripted-runtime-carriers"},
            {fact["name"] for fact in facts if fact["group"] == "scripted-runtime-carriers"},
            {effect["recipe"] for fact in facts for effect in fact["effects"] if effect["type"] == "change-recipe-productivity"},
            {effect["ammo_category"] for fact in facts for effect in fact["effects"] if effect["type"] == "gun-speed"},
        )

    def test_exact_independent_inventory_and_published_owner_closure(self):
        for key, oracle_name, owners in (("base", "base-f210", set()), ("space_age", "space-age-f210", OWNERS)):
            public, state, scripted, recipes, guns = self.expected(oracle_name)
            plan = self.plan[key]
            with self.subTest(key=key):
                self.assertEqual(public, {row["name"] for row in plan["public"]})
                self.assertEqual(state, {row["name"] for row in plan["state"]})
                self.assertEqual(scripted, set(plan["scripted"]))
                self.assertEqual(recipes, set(plan["recipes"]))
                self.assertEqual(guns, set(plan["guns"]))
                self.assertEqual(owners, set(plan["native_owners"]))
                credits = {
                    f"mir-native-credit-{family}-{recipe}-{direction}"
                    for family, main, recipe in DESCRIPTORS if main in public for direction in ("positive", "negative")
                }
                self.assertEqual(credits, set(plan["credits"]))
        self.assertEqual((53, 71, 20, 24), (len(self.plan["base"]["public"]), len(self.plan["space_age"]["public"]), len(self.plan["base"]["credits"]), len(self.plan["space_age"]["credits"])))
        self.assertEqual((53, 69), (len(self.plan["base"]["state"]), len(self.plan["space_age"]["state"])))
        self.assertEqual({"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"}, set(self.plan["space_age"]["scripted"]))
        self.assertTrue({"recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_cargo_landing_pad_count-1"} <= {row["name"] for row in self.plan["space_age"]["state"]})
        owners = {
            row["native_owner_identity"]
            for row in self.oracle["space-age-f210"]["captured_maximum_level_bindings"]["bindings"]
            if row["operation"] == "preserve_native_owner"
        }
        self.assertEqual(OWNERS, owners)

    def test_stage_data_guard_accelerates_only_exact_f210_gear(self):
        self.lua.execute("""
          function run_data(path, common, catalogue, f210_catalogue, raw, mods)
            local env = {data={raw=raw}, mods=mods}
            env.require = function(name)
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_data_final" then
                return assert(loadfile(common, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                return assert(loadfile(catalogue, "t", env))()
              end
              if name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue" then
                return assert(loadfile(f210_catalogue, "t", env))()
              end
              error("unexpected fixture module: " .. tostring(name))
            end
            setmetatable(env, {__index=_G})
            local ok, message = pcall(function() assert(loadfile(path, "t", env))() end)
            return {ok=ok, message=tostring(message), raw=raw}
          end
        """)
        for stage, mir in (("published-4.7", "4.7.21002"), ("mir5", "5.0.21000")):
            for space in (False, True):
                effects = [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]
                if space:
                    effects.insert(0, {"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": .1})
                gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 60}, "effects": effects}
                raw = {"technology": {"recipe-prod-research_gears-1": gear}, "unchanged": {"value": 17}}
                mods = {"base": "2.1.23", "more-infinite-research": mir, "mir-fixture-mir5-full-catalogue-upgrade": "0.1.0" if stage == "published-4.7" else "0.2.0"}
                if space:
                    mods.update({"elevated-rails": "2.1.23", "quality": "2.1.23", "recycler": "2.1.23", "space-age": "2.1.23"})
                with self.subTest(stage=stage, space=space):
                    result = self.lua.eval("run_data")((F210 / stage / "data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / stage / "catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, raw), lua(self.lua, mods))
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]
                    self.assertEqual((None, "1", 1), (actual.get("count"), actual["count_formula"], actual["time"]))
                    self.assertEqual(17, py(result["raw"])["unchanged"]["value"])
        gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 61}, "effects": [{"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]}
        result = self.lua.eval("run_data")((F210 / "mir5/data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / "mir5/catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, {"technology": {"recipe-prod-research_gears-1": gear}}), lua(self.lua, {"base": "2.1.23", "more-infinite-research": "5.0.21000", "mir-fixture-mir5-full-catalogue-upgrade": "0.2.0"}))
        self.assertFalse(result["ok"])
        self.assertIn("workload differs", str(result["message"]))
        self.assertEqual(61, py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]["time"])
        gear = {"max_level": "infinite", "unit": {"count_formula": "8000*2^(L-1)", "time": 60}, "effects": [{"type": "change-recipe-productivity", "recipe": "casting-iron-gear-wheel", "change": .1}, {"type": "change-recipe-productivity", "recipe": "iron-gear-wheel", "change": .1}]}
        result = self.lua.eval("run_data")((F210 / "published-4.7/data-final-fixes.lua").as_posix(), (SHARED / "data-final-fixes.lua").as_posix(), (F210 / "published-4.7/catalogue.lua").as_posix(), (SHARED / "f210-catalogue.lua").as_posix(), lua(self.lua, {"technology": {"recipe-prod-research_gears-1": gear}}), lua(self.lua, {"base": "2.1.23", "elevated-rails": "2.1.23", "quality": "2.1.23", "space-age": "2.1.23", "more-infinite-research": "4.7.21002", "mir-fixture-mir5-full-catalogue-upgrade": "0.1.0"}))
        self.assertFalse(result["ok"])
        self.assertIn("Space Age closure differs", str(result["message"]))
        self.assertEqual(60, py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]["time"])

    def test_shared_control_registers_f210_stages_without_runtime_reads(self):
        for stage in ("published-4.7", "mir5"):
            with self.subTest(stage=stage):
                self.lua.globals().control_path = (F210 / stage / "control.lua").as_posix()
                self.lua.globals().catalogue_path = (F210 / stage / "catalogue.lua").as_posix()
                self.lua.globals().f210_catalogue_path = (SHARED / "f210-catalogue.lua").as_posix()
                self.lua.globals().common_control_path = (SHARED / "control.lua").as_posix()
                self.lua.globals().source_stage = stage == "published-4.7"
                self.lua.execute("""
                  function parse_f210_control()
                    local callbacks, forbidden = {events={}}, {}
                    local env = {
                      script={on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                        on_configuration_changed=function(fn) callbacks.configuration=fn end,
                        on_event=function(event, fn) callbacks.events[event]=fn end,
                        active_mods={base="2.1.23", ["more-infinite-research"]=source_stage and "4.7.21002" or "5.0.21000",
                          ["mir-fixture-mir5-full-catalogue-upgrade"]=source_stage and "0.1.0" or "0.2.0"}},
                      defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
                    }
                    env.require=function(name)
                        if name == "__mir-fixture-mir5-full-catalogue-upgrade__/fixture_control" then
                          return assert(loadfile(common_control_path, "t", env))()
                        end
                        if name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue" then
                          return assert(loadfile(catalogue_path, "t", env))()
                        end
                        assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/f210_catalogue")
                        return assert(loadfile(f210_catalogue_path, "t", env))()
                      end
                    env._G=env
                    setmetatable(env,{__index=function(_,key)
                      if key == "game" or key == "storage" then forbidden[key]=true; return nil end
                      return _G[key]
                    end})
                    local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
                    return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
                  end
                """)
                result = self.lua.eval("parse_f210_control")()
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                if stage == "published-4.7":
                    self.assertIsNotNone(result["callbacks"]["init"])
                else:
                    self.assertIsNotNone(result["callbacks"]["configuration"])

    def test_f210_runtime_force_schema_when_local_api_is_available(self):
        runtime_api = f210_runtime_api_path()
        if runtime_api is None:
            self.skipTest("F210 runtime API documentation is not installed")
        document = json.loads(runtime_api.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.1.23")
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"]: row for row in lua_force["attributes"]}
        fixture_fields = set(self.plan["force_fields"])
        self.assertTrue(fixture_fields <= set(fields))
        self.assertEqual(("double", "double"), (fields["max_cargo_bay_unloading_distance"]["read_type"], fields["max_cargo_bay_unloading_distance"]["write_type"]))
        self.assertEqual(("uint32", "uint32"), (fields["cargo_landing_pad_limit"]["read_type"], fields["cargo_landing_pad_limit"]["write_type"]))

    def test_profiles_and_shared_staging_contract_are_explicit(self):
        for stage, mir, fixture in (("published-4.7", "4.7.21002", "0.1.0"), ("mir5", "5.0.21000", "0.2.0")):
            info = json.loads((F210 / stage / "info.json").read_text(encoding="utf-8"))
            with self.subTest(info_stage=stage):
                self.assertEqual(("mir-fixture-mir5-full-catalogue-upgrade", fixture, "2.1"), (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual([
                    "base = 2.1.23",
                    "? elevated-rails = 2.1.23",
                    "? quality = 2.1.23",
                    "? recycler = 2.1.23",
                    "? space-age = 2.1.23",
                    f"more-infinite-research = {mir}",
                ], info["dependencies"])
        for profile in ("base", "space-age"):
            for stage, mir, fixture, archive in (("published-4.7", "4.7.21002", "0.1.0", PUBLISHED), ("mir5", "5.0.21000", "0.2.0", CANDIDATE)):
                data = json.loads((PROFILES / f"full-catalogue-upgrade-{stage}-{profile}-f210-2123.json").read_text(encoding="utf-8"))
                expected_mods = [
                    {"name": "base", "version": "2.1.23", "enabled": True},
                ]
                if profile == "space-age":
                    expected_mods.extend([
                        {"name": "elevated-rails", "version": "2.1.23", "enabled": True},
                        {"name": "quality", "version": "2.1.23", "enabled": True},
                        {"name": "recycler", "version": "2.1.23", "enabled": True},
                        {"name": "space-age", "version": "2.1.23", "enabled": True},
                    ])
                expected_mods.extend([
                    {"name": "mir-fixture-mir5-active-mods-observer", "version": "0.1.0", "enabled": True},
                    {"name": "more-infinite-research", "version": mir, "enabled": True},
                    {"name": "mir-fixture-mir5-full-catalogue-upgrade", "version": fixture, "enabled": True},
                ])
                with self.subTest(profile=profile, stage=stage):
                    self.assertEqual(("f210", "2.1"), (data["target"], data["factorio_line"]))
                    self.assertEqual({"version": "2.1.23", "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"}, data["engine"])
                    self.assertEqual(expected_mods, data["mods"])
                    self.assertEqual({"mir-fixture-mir5-active-mods-observer_0.1.0.zip": OBSERVER, f"more-infinite-research_{mir}.zip": archive}, data["archive_sha256"])
        self.assertEqual((F210 / "published-4.7/control.lua").read_bytes(), (F210 / "mir5/control.lua").read_bytes())
        self.assertEqual((F210 / "published-4.7/data-final-fixes.lua").read_bytes(), (F210 / "mir5/data-final-fixes.lua").read_bytes())
        for path in FIXTURE.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("__more-infinite-research__", text)
            self.assertNotIn('require("research.', text)
            self.assertNotIn('require("compatibility.', text)
        common = (SHARED / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local SAVE = "mir5-native-complete"', common)
        self.assertIn("script.on_load(function()", common)
        self.assertIn("assert_credits(player, plan", common)
        self.assertIn("assert_successor_snapshot", common)
        self.assertIn("queued_progress=.42", common)
        self.assertIn("paused_progress=.27", common)
        self.assertNotIn("productivity_bonus =", common)
        self.assertNotIn("research_unit_count =", common)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FullCatalogueUpgradeF210FixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
