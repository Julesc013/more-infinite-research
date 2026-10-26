"""Independent F210 SE/K2SE data-final publication over upstream-only context."""

import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source"
FACTS_PATH = ROOT / "tests/fixtures/space-exploration-f210-captured-facts.json"
CONTEXT_PATH = ROOT / "tests/fixtures/space-exploration-f210-upstream-context.json.gz"
MAX_CONTEXT_BYTES = 2 * 1024 * 1024
UPSTREAM_RAW_SHA256 = {
    "se": "24B2518F425CD57DAE869D37D0D6ED468F011B228B8D357E039306E59CE00BBD",
    "k2se": "53D55E243F1E2B5A7D861E736F12D16D4356E56A6FAF0EC28C0B76C78E06074F",
}


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, nested in value.items():
            table[key] = _lua_value(lua, nested)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, nested in enumerate(value, start=1):
            table[index] = _lua_value(lua, nested)
        return table
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(nested) for key, nested in items.items()}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _technology_contract(row):
    """The complete emitted behaviour asserted by this pipeline control."""
    return {
        "enabled": row.get("enabled", True),
        "max_level": row.get("max_level"),
        "unit": row["unit"],
        "prerequisites": row.get("prerequisites", []),
        "effects": row.get("effects", []),
    }


class SpaceExplorationPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("SE pipeline context exceeds its 2 MiB compressed ceiling")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        if cls.context.get("schema") != "MIR5SpaceExplorationUpstreamPipelineContextV1":
            raise AssertionError("SE pipeline context schema changed")
        for case, expected_hash in UPSTREAM_RAW_SHA256.items():
            if cls.context["cases"][case].get("source_data_raw_dump_sha256") != expected_hash:
                raise AssertionError(f"{case} upstream raw provenance changed")

    def stage(self, case, startup=None):
        context = self.context["cases"][case]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, deepcopy(context["raw"]))
        lua.globals().active_mods = _lua_value(lua, context["selection"])
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods = active_mods
          script = nil
          helpers = {}
          log = function() end
          settings = {startup = startup_values}
          emitted = {}; publications = 0
          data = {raw = captured_raw}
          function data:extend(rows)
            publications = publications + 1
            for _, row in ipairs(rows) do
              self.raw[row.type] = self.raw[row.type] or {}
              assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
              self.raw[row.type][row.name] = row
              emitted[row.type] = emitted[row.type] or {}
              emitted[row.type][row.name] = row
            end
          end
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          assert(loadfile(player_root .. "/data.lua"))()
          assert(loadfile(player_root .. "/data-final-fixes.lua"))()
        ''')
        return lua

    def assert_pipeline_rows(self, case):
        lua = self.stage(case)
        emitted = _plain(lua.globals().emitted).get("technology", {})
        expected = self.facts["captures"][case]["technologies"]
        boundary = self.context["pre_engine_prerequisite_boundary"]
        pre_engine_prerequisites = (
            boundary["frozen_b2_c01_pre_engine"]["prerequisites"]
            if case == "se"
            else boundary["k2se_pre_engine_equality_check"]["prerequisites"]
        )
        public = {name: row for name, row in emitted.items() if not name.startswith("mir-native-credit-")}
        carriers = {name: row for name, row in emitted.items() if name.startswith("mir-native-credit-")}
        self.assertEqual(set(public), set(expected), case)
        self.assertEqual(20, len(carriers), case)
        self.assertTrue(all(row.get("hidden") is True and row.get("enabled") is False for row in carriers.values()))
        for name, expected_row in expected.items():
            actual_contract = _technology_contract(public[name])
            expected_contract = _technology_contract(expected_row)
            # The 19 rows below have an observed Factorio data-stage/write-data
            # boundary in the frozen B2 package.  Keep that finite pre-engine
            # contract exact; do not emulate the engine with a prerequisite
            # pruner or weaken prerequisite comparison for any other row.
            if name in pre_engine_prerequisites:
                expected_contract["prerequisites"] = pre_engine_prerequisites[name]
            self.assertEqual(actual_contract, expected_contract, name)
        # This target is admitted only after the one data-final product pass;
        # a constructor-only comparison cannot observe it.
        advanced_circuit = public["recipe-prod-research_advanced_circuit-1"]
        self.assertIn(
            "se-recycle-substation",
            [effect.get("recipe") for effect in advanced_circuit["effects"] if effect["type"] == "change-recipe-productivity"],
        )
        self.assertEqual(2, lua.globals().publications)

    def test_upstream_projection_is_bounded_and_excludes_graphics_or_autoplace(self):
        self.assertLessEqual(CONTEXT_PATH.stat().st_size, MAX_CONTEXT_BYTES)
        rules = self.context["projection_rules"]
        self.assertIn("upstream", rules["source"])
        self.assertIn("excluded", rules)
        forbidden = {"icon", "icons", "graphics", "autoplace"}

        def visit(value):
            if isinstance(value, dict):
                self.assertTrue(forbidden.isdisjoint(value), value.keys())
                for nested in value.values():
                    visit(nested)
            elif isinstance(value, list):
                for nested in value:
                    visit(nested)

        for name, case in self.context["cases"].items():
            with self.subTest(case=name):
                raw = case["raw"]
                visit(raw)
                self.assertEqual(case["projection_counts"], {kind: len(rows) for kind, rows in raw.items()})
                self.assertTrue(raw["recipe"])
                self.assertTrue(raw["lab"])
                self.assertTrue(raw["technology"])
                # Science/technology requests also name intentionally absent
                # Space Age subjects in these Base-only upstream captures.
                for field in ("required_product_recipe_names", "required_science_item_names", "required_technology_names"):
                    requested = case[field]
                    self.assertEqual(len(requested), len(set(requested)), field)
                    self.assertTrue(all(isinstance(value, str) and value for value in requested), field)
                self.assertFalse(set(case["required_product_recipe_names"]) - raw["recipe"].keys(),
                                 "projected context lost a required product recipe")

    def test_se_full_data_final_publication_matches_all_55_independent_rows(self):
        self.assert_pipeline_rows("se")

    def test_k2se_full_data_final_publication_matches_all_55_independent_rows(self):
        self.assert_pipeline_rows("k2se")

    def test_frozen_pre_engine_prerequisite_boundary_is_explicit_and_native_check_remains_required(self):
        boundary = self.context["pre_engine_prerequisite_boundary"]
        known_rows = boundary["known_rows"]
        frozen = boundary["frozen_b2_c01_pre_engine"]
        k2se = boundary["k2se_pre_engine_equality_check"]
        native = boundary["native_write_data_readbacks"]

        for case in ("se", "k2se"):
            self.assertEqual(self.facts["captures"][case]["source_data_raw_dump_sha256"],
                             native[case]["published_data_raw_dump_sha256"], case)
        self.assertNotEqual(native["se"]["published_data_raw_dump_sha256"],
                            native["se"]["candidate_data_raw_dump_sha256"])
        self.assertEqual(self.context["cases"]["se"]["source_data_raw_dump_sha256"],
                         frozen["upstream_data_raw_dump_sha256"])

        self.assertEqual("MIR5SpaceExplorationF210PrerequisiteBoundaryV1", boundary["schema"])
        self.assertEqual("required", boundary["new_package_native_prerequisite_check"])
        self.assertEqual(set(known_rows), set(frozen["prerequisites"]))
        self.assertEqual(frozen["prerequisites"], k2se["prerequisites"])
        self.assertTrue(k2se["equals_frozen_b2_c01_pre_engine"])

        expected_native_se = {
            name: self.facts["captures"]["se"]["technologies"][name].get("prerequisites", [])
            for name in known_rows
        }
        expected_native_k2se = {
            name: self.facts["captures"]["k2se"]["technologies"][name].get("prerequisites", [])
            for name in known_rows
        }
        self.assertEqual(expected_native_se, native["se"]["published_prerequisites"])
        self.assertEqual(expected_native_se, native["se"]["candidate_prerequisites"])
        self.assertEqual(expected_native_k2se, native["k2se"]["published_prerequisites"])
        self.assertEqual(
            "unavailable-pre-data-final: frozen B2 c03 refused the partial K2 selection",
            native["k2se"]["candidate_data_raw_dump_status"],
        )
        for name in known_rows:
            self.assertNotEqual(frozen["prerequisites"][name], expected_native_se[name], name)

    def test_nondefault_stream_setting_is_applied_and_declared_cap_remains_bounded(self):
        default = _plain(self.stage("se").globals().emitted)["technology"]["recipe-prod-research_belts-1"]
        configured = _plain(self.stage("se", {
            "ips-effect-per-level-research_belts": {"value": 17},
            "ips-cost-growth-research_belts": {"value": 3},
        }).globals().emitted)["technology"]["recipe-prod-research_belts-1"]
        default_effects = [effect["change"] for effect in default["effects"] if effect["type"] == "change-recipe-productivity"]
        configured_effects = [effect["change"] for effect in configured["effects"] if effect["type"] == "change-recipe-productivity"]
        self.assertTrue(default_effects)
        self.assertEqual([value * 1.7 for value in default_effects], configured_effects)
        lua = self.stage("se")
        settings = _plain(lua.execute('return require("research.settings").prototypes()'))
        growth = next(row for row in settings if row["name"] == "ips-cost-growth-research_belts")
        effect = next(row for row in settings if row["name"] == "ips-effect-per-level-research_belts")
        self.assertEqual(1000, growth["maximum_value"])
        self.assertEqual(1000000, effect["maximum_value"])

    def test_deferred_recipe_safety_removes_a_missing_target_before_publication(self):
        broken = deepcopy(self.context["cases"]["se"]["raw"])
        broken["recipe"].pop("se-recycle-substation")
        original = self.context["cases"]["se"]["raw"]
        self.context["cases"]["se"]["raw"] = broken
        try:
            emitted = _plain(self.stage("se").globals().emitted)["technology"]
            advanced_circuit = emitted["recipe-prod-research_advanced_circuit-1"]
            self.assertNotIn(
                "se-recycle-substation",
                [effect.get("recipe") for effect in advanced_circuit["effects"] if effect["type"] == "change-recipe-productivity"],
            )
        finally:
            self.context["cases"]["se"]["raw"] = original


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SpaceExplorationPipelineTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
