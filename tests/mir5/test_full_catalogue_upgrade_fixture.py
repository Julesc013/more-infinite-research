import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/mir5/fixtures/full-catalogue-upgrade"
PROFILES = ROOT / "tests/mir5/profiles"
ORACLE = ROOT / "spec/mir5/inventory/modern-f200-470.json"
F200_RUNTIME_API = Path("D:/Programs/Factorio/2.0/doc-html/runtime-api.json")
OWNERS = {"low-density-structure-productivity", "plastic-bar-productivity", "processing-unit-productivity", "rocket-fuel-productivity", "steel-plate-productivity"}
DESCRIPTORS = (("research_copper", "recipe-prod-research_copper-1", "copper-plate"), ("research_iron", "recipe-prod-research_iron-1", "iron-plate"), ("research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"), ("research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"), ("research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"), ("research_grenades", "recipe-prod-research_grenades-1", "grenade"), ("research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"), ("research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"), ("research_concrete", "recipe-prod-research_concrete-1", "stone-brick"), ("research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"))


def py(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys): return [py(value[key]) for key in range(1, max(keys)+1)]
        return {key: py(value[key]) for key in keys}
    return value


def lua(runtime, value):
    if isinstance(value, dict):
        out = runtime.table()
        for key, item in value.items(): out[key] = lua(runtime, item)
        return out
    if isinstance(value, list):
        out = runtime.table()
        for index, item in enumerate(value, 1): out[index] = lua(runtime, item)
        return out
    return value


class FullCatalogueUpgradeFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.oracle = {p["id"]: p for p in json.loads(ORACLE.read_text(encoding="utf-8"))["profiles"]}

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("function load_plan(path) return assert(loadfile(path))() end")
        self.plan = py(self.lua.eval("load_plan")((FIXTURE / "published-4.7/catalogue.lua").as_posix()))

    def expected(self, name):
        facts = self.oracle[name]["technology_owner_progression_facts"]
        return ({f["name"] for f in facts}, {f["name"] for f in facts if f["group"] != "scripted-runtime-carriers"}, {f["name"] for f in facts if f["group"] == "scripted-runtime-carriers"}, {e["recipe"] for f in facts for e in f["effects"] if e["type"] == "change-recipe-productivity"}, {e["ammo_category"] for f in facts for e in f["effects"] if e["type"] == "gun-speed"})

    def test_exact_oracle_identity_effect_and_credit_closure(self):
        for key, oracle_name, owners in (("base", "base-f200", set()), ("space_age", "space-age-f200", OWNERS)):
            public, state, scripted, recipes, guns = self.expected(oracle_name)
            plan = self.plan[key]
            with self.subTest(key=key):
                self.assertEqual(public, {row["name"] for row in plan["public"]})
                self.assertEqual(state, {row["name"] for row in plan["state"]})
                self.assertEqual(scripted, set(plan["scripted"]))
                self.assertEqual(recipes, set(plan["recipes"]))
                self.assertEqual(guns, set(plan["guns"]))
                self.assertEqual(owners, set(plan["native_owners"]))
                credits = {f"mir-native-credit-{family}-{recipe}-{direction}" for family, main, recipe in DESCRIPTORS if main in public for direction in ("positive", "negative")}
                self.assertEqual(credits, set(plan["credits"]))
        self.assertEqual((54, 69, 20, 24), (len(self.plan["base"]["public"]), len(self.plan["space_age"]["public"]), len(self.plan["base"]["credits"]), len(self.plan["space_age"]["credits"])))
        self.assertEqual({"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"}, set(self.plan["space_age"]["scripted"]))

    def test_stage_data_guard_accelerates_exact_gear_only(self):
        self.lua.execute("function run_data(path, raw, mods) data={raw=raw}; _G.mods=mods; local ok, message=pcall(function() assert(loadfile(path))() end); return {ok=ok,message=tostring(message),raw=raw} end")
        for stage, mir in (("published-4.7", "4.7.20002"), ("mir5", "5.0.20000")):
            for space in (False, True):
                effects = [{"type":"change-recipe-productivity", "recipe":"iron-gear-wheel", "change":.1}]
                if space: effects.insert(0, {"type":"change-recipe-productivity", "recipe":"casting-iron-gear-wheel", "change":.1})
                gear = {"max_level":"infinite", "unit":{"count_formula":"8000*2^(L-1)", "time":60}, "effects":effects}
                raw = {"technology":{"recipe-prod-research_gears-1":gear}, "unchanged":{"value":17}}
                mods = {"base":"2.0.77", "more-infinite-research":mir}
                if space: mods.update({"space-age":"2.0.77", "elevated-rails":"2.0.77", "quality":"2.0.77"})
                with self.subTest(stage=stage, space=space):
                    result = self.lua.eval("run_data")((FIXTURE / stage / "data-final-fixes.lua").as_posix(), lua(self.lua, raw), lua(self.lua, mods))
                    self.assertTrue(result["ok"], result["message"])
                    actual = py(result["raw"])["technology"]["recipe-prod-research_gears-1"]["unit"]
                    self.assertEqual((None, "1", 1), (actual.get("count"), actual["count_formula"], actual["time"]))
                    self.assertEqual(17, py(result["raw"])["unchanged"]["value"])
        gear = {"max_level":"infinite", "unit":{"count_formula":"8000*2^(L-1)", "time":61}, "effects":[{"type":"change-recipe-productivity", "recipe":"iron-gear-wheel", "change":.1}]}
        result = self.lua.eval("run_data")((FIXTURE / "mir5/data-final-fixes.lua").as_posix(), lua(self.lua, {"technology":{"recipe-prod-research_gears-1":gear}}), lua(self.lua, {"base":"2.0.77", "more-infinite-research":"5.0.20000"}))
        self.assertFalse(result["ok"]); self.assertIn("workload differs", str(result["message"])); self.assertEqual(61, gear["unit"]["time"])

    def test_controls_register_without_game_or_storage_reads(self):
        for stage in ("published-4.7", "mir5"):
            with self.subTest(stage=stage):
                self.lua.globals().control_path = (FIXTURE / stage / "control.lua").as_posix()
                self.lua.globals().catalogue_path = (FIXTURE / stage / "catalogue.lua").as_posix()
                self.lua.execute("""
                  function parse_full_catalogue_control()
                    local callbacks, forbidden = {events={}}, {}
                    local env = {
                      require=function(name)
                        assert(name == "__mir-fixture-mir5-full-catalogue-upgrade__/catalogue")
                        return assert(loadfile(catalogue_path, "t", _G))()
                      end,
                      script={on_init=function(fn) callbacks.init=fn end, on_load=function(fn) callbacks.load=fn end,
                        on_configuration_changed=function(fn) callbacks.configuration=fn end,
                        on_event=function(event, fn) callbacks.events[event]=fn end},
                      defines={events={on_research_finished=1,on_tick=2},inventory={lab_input=1}},
                    }
                    env._G=env
                    setmetatable(env,{__index=function(_,key)
                      if key == "game" or key == "storage" then forbidden[key]=true; return nil end
                      return _G[key]
                    end})
                    local ok,message=pcall(function() assert(loadfile(control_path, "t", env))() end)
                    return {ok=ok,message=tostring(message),callbacks=callbacks,forbidden=forbidden}
                  end
                """)
                result = self.lua.eval("parse_full_catalogue_control")()
                self.assertTrue(result["ok"], result["message"])
                self.assertIsNone(result["forbidden"]["game"])
                self.assertIsNone(result["forbidden"]["storage"])
                self.assertIsNotNone(result["callbacks"]["load"])
                self.assertIsNotNone(result["callbacks"]["events"][1])
                self.assertIsNotNone(result["callbacks"]["events"][2])
                if stage == "published-4.7": self.assertIsNotNone(result["callbacks"]["init"])
                else: self.assertIsNotNone(result["callbacks"]["configuration"])

    def test_f200_force_field_schema_when_local_api_is_available(self):
        if not F200_RUNTIME_API.is_file():
            self.skipTest("F200 runtime API documentation is not installed")
        document = json.loads(F200_RUNTIME_API.read_text(encoding="utf-8"))
        lua_force = next(row for row in document["classes"] if row["name"] == "LuaForce")
        fields = {row["name"] for row in lua_force["attributes"]}
        fixture_fields = set(self.plan["force_fields"])
        self.assertIn("character_trash_slot_count", fixture_fields)
        self.assertNotIn("character_logistic_trash_slots", fixture_fields)
        self.assertTrue(fixture_fields <= fields)

    def test_profiles_controls_and_native_boundaries_are_explicit(self):
        expected_hash = {"mir-fixture-mir5-active-mods-observer_0.1.0.zip":"723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"}
        for profile in ("base", "space-age"):
            for stage, mir, fixture in (("published-4.7", "4.7.20002", "0.1.0"), ("mir5", "5.0.20000", "0.2.0")):
                data = json.loads((PROFILES / f"full-catalogue-upgrade-{stage}-{profile}-f200-2077.json").read_text(encoding="utf-8"))
                mods = {row["name"]: row["version"] for row in data["mods"]}
                with self.subTest(profile=profile, stage=stage):
                    self.assertEqual(("f200", "2.0", "2.0.77"), (data["target"], data["factorio_line"], data["engine"]["version"]))
                    self.assertEqual((mir, fixture), (mods["more-infinite-research"], mods["mir-fixture-mir5-full-catalogue-upgrade"]))
                    self.assertEqual(profile == "space-age", "space-age" in mods)
                    self.assertEqual(expected_hash, data["archive_sha256"])
        self.assertEqual((FIXTURE / "published-4.7/catalogue.lua").read_bytes(), (FIXTURE / "mir5/catalogue.lua").read_bytes())
        for path in FIXTURE.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("__more-infinite-research__", text)
            self.assertNotIn('require("research.', text)
            self.assertNotIn('require("compatibility.', text)
        source = (FIXTURE / "published-4.7/control.lua").read_text(encoding="utf-8")
        successor = (FIXTURE / "mir5/control.lua").read_text(encoding="utf-8")
        for text in (source, successor):
            self.assertIn('local SAVE = "mir5-native-complete"', text)
            self.assertIn("script.on_load(function()", text)
            self.assertNotIn("productivity_bonus =", text)
            self.assertNotIn("research_unit_count =", text)
        self.assertIn("queued_progress=.42", source); self.assertIn("paused_progress=.27", source)
        self.assertIn("assert_credits(player, plan", successor); self.assertIn("assert_successor_snapshot", successor)
        for text in (source, successor):
            self.assertIn("player.research_queue_enabled = true", text)
            self.assertIn("paused_snapshot", text)
            self.assertIn("assert_same_snapshot(paused, plan, state.paused_snapshot", text)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FullCatalogueUpgradeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
