"""Independent F210 Py HighTech data-final pipeline control.

The two raw contexts are upstream-only. Published MIR4 rows remain in the
separate captured-facts fixture, so this control never manufactures expected
behaviour from a current candidate data stage.
"""

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
CONTEXT_PATH = ROOT / "tests/fixtures/py-f210-upstream-context.json.gz"
FACTS_PATH = ROOT / "tests/fixtures/py-f210-captured-facts.json.gz"
MAX_CONTEXT_BYTES = 2 * 1024 * 1024
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
CONTINUATION_IDS = {
    "braking-force-8",
    "inserter-capacity-bonus-8",
    "laser-shooting-speed-8",
    "research-speed-7",
    "weapon-shooting-speed-7",
    "worker-robots-storage-4",
}
DISABLED_BATTERY = "recipe-prod-research_batteries-1"
BASE_LITERAL_NAME_PRESENTATION_REPAIRS = {
    # The published rows retain the original shape as captured evidence.  The
    # two substitutions were invalid F210 Base locale children; the enclosing
    # MIR keys are literal titles in every shipped locale.
    "recipe-prod-research_mining_drill-1": {
        "captured": ["technology-name.more-infinite-research.research_mining_drill",
                     ["item-name.electric-mining-drill"]],
        "emitted": ["technology-name.more-infinite-research.research_mining_drill"],
    },
    "recipe-prod-research_walls-1": {
        "captured": ["technology-name.more-infinite-research.research_walls",
                     ["item-name.stone-wall"]],
        "emitted": ["technology-name.more-infinite-research.research_walls"],
    },
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


def _repair_base_literal_name_presentation(rows):
    """Use exactly the two reviewed successor presentation values."""
    repaired = deepcopy(rows)
    for technology, expected in BASE_LITERAL_NAME_PRESENTATION_REPAIRS.items():
        if repaired.get(technology, {}).get("localised_name") != expected["captured"]:
            raise AssertionError(f"captured Py presentation changed: {technology}")
        repaired[technology]["localised_name"] = deepcopy(expected["emitted"])
    return repaired


class PyF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("Py F210 upstream context exceeds its 2 MiB compressed ceiling")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        if cls.context.get("schema") != "MIR5PyF210UpstreamPipelineContextV1":
            raise AssertionError("Py F210 upstream context schema changed")
        if cls.facts.get("schema") != "MIR5PyF210CapturedFactsV1":
            raise AssertionError("Py F210 captured facts schema changed")

    @staticmethod
    def _capture_key(case):
        return {
            "q001": "q001_py_hightech_base",
            "q003": "q003_py_hightech_productivity_base",
        }[case]

    def stage(self, case, startup=None):
        context = self.context["cases"][case]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, deepcopy(context["raw"]))
        lua.globals().active_mods = _lua_value(lua, deepcopy(context["selection"]))
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, script, helpers, log = active_mods, nil, {}, function() end
          settings = {startup = startup_values}
          emitted, publications = {}, 0
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
          emitted, publications = {}, 0
          assert(loadfile(player_root .. "/data-final-fixes.lua"))()
        ''')
        return lua

    def stage_failure(self, case, mutate):
        context = self.context["cases"][case]
        raw = deepcopy(context["raw"])
        mutate(raw)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, deepcopy(context["selection"]))
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, script, helpers, log = active_mods, nil, {}, function() end
          settings = {startup = {}}
          emitted = {}
          data = {raw = captured_raw}
          function data:extend(rows)
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
          emitted = {}
          final_ok, final_error = pcall(function() assert(loadfile(player_root .. "/data-final-fixes.lua"))() end)
        ''')
        return lua

    def _expected_capture(self, case):
        return self.facts["captures"][self._capture_key(case)]

    def _technology_rows(self, lua):
        return _plain(lua.globals().emitted).get("technology", {})

    def test_context_is_bounded_upstream_only_and_preserves_observation_scope(self):
        self.assertLessEqual(CONTEXT_PATH.stat().st_size, MAX_CONTEXT_BYTES)
        self.assertEqual(self.context["facts_fixture"]["path"], "tests/fixtures/py-f210-captured-facts.json.gz")
        self.assertEqual(self.context["facts_fixture"]["expected_published_productivity_rows_per_case"], 49)
        self.assertEqual(self.context["facts_fixture"]["expected_published_continuations_per_case"], 6)
        self.assertIn("upstream", self.context["projection_rules"]["source"])
        self.assertIn("no published or candidate prototype dump", self.context["projection_rules"]["source"])
        for case in ("q001", "q003"):
            context = self.context["cases"][case]
            expected = self._expected_capture(case)
            capture = context["capture"]
            self.assertEqual("MIR5PrototypeCaptureV1", capture["kind"])
            self.assertEqual("completed-data-stage-observation-only", capture["status"])
            self.assertFalse(capture["native_qualification"])
            self.assertEqual(F210_SHA256, capture["engine"]["sha256"])
            self.assertEqual(expected["arms"]["upstream"]["result_sha256"], capture["result_sha256"])
            self.assertEqual(expected["data_raw"]["upstream"]["sha256"], context["source_data_raw_dump_sha256"])
            self.assertEqual(expected["data_raw"]["upstream"]["bytes"], context["source_data_raw_dump_bytes"])
            self.assertIn("pyhightech", context["selection"])
            self.assertIn("pycoalprocessing", context["selection"])
            self.assertIn("pyalienlife", context["selection"])
            self.assertEqual("py_productivity" in context["selection"], case == "q003")
            self.assertTrue(context["raw"]["recipe"])
            self.assertTrue(context["raw"]["technology"])
            self.assertTrue(context["raw"]["lab"])
            self.assertNotIn("candidate", context["raw"])
            self.assertNotIn("published", context["raw"])
            for arm in ("published", "candidate"):
                self.assertEqual(expected["arms"][arm], self.context["nonqualification_scope"][case][arm])

    def assert_full_pipeline(self, case):
        rows = self._technology_rows(self.stage(case))
        expected = self._expected_capture(case)
        published = _repair_base_literal_name_presentation(expected["published_rows"])
        continuations = expected["published_continuations"]
        actual_productivity = {
            name: row for name, row in rows.items()
            if name.startswith("recipe-prod-research_") and name != DISABLED_BATTERY
        }
        self.assertEqual(set(published), set(actual_productivity), case)
        self.assertEqual(published, actual_productivity, case)
        self.assertEqual(CONTINUATION_IDS, {row["name"] for row in continuations.values()})
        self.assertEqual(
            {row["name"]: row for row in continuations.values()},
            {name: rows[name] for name in CONTINUATION_IDS},
            case,
        )
        battery = rows[DISABLED_BATTERY]
        self.assertFalse(battery["enabled"])
        # An empty Factorio Lua table has no array shape when read through
        # Lupa. Assert its semantic emptiness instead of inventing a list
        # representation for this deliberately effect-free saved identity.
        self.assertFalse(battery["effects"])
        self.assertEqual(DISABLED_BATTERY, battery["name"])
        return rows

    def test_q001_full_data_final_matches_independent_published_rows_and_continuations(self):
        self.assert_full_pipeline("q001")

    def test_q003_productivity_addon_is_separately_selected_and_matches_its_independent_rows(self):
        q001_rows = self.assert_full_pipeline("q001")
        q003_rows = self.assert_full_pipeline("q003")
        q001_expected = self._expected_capture("q001")["published_rows"]
        q003_expected = self._expected_capture("q003")["published_rows"]
        changed = {name for name in q001_expected if q001_expected[name] != q003_expected[name]}
        self.assertEqual(
            {
                "recipe-prod-research_copper-1", "recipe-prod-research_copper_cable-1",
                "recipe-prod-research_engine-1", "recipe-prod-research_gears-1", "recipe-prod-research_iron-1",
                "recipe-prod-research_iron_sticks-1", "recipe-prod-research_sulfur-1",
            },
            changed,
        )
        for name in changed:
            self.assertNotEqual(q001_rows[name], q003_rows[name], name)

    def test_named_native_continuation_preflight_refuses_before_technology_publication(self):
        lua = self.stage_failure("q001", lambda raw: raw["technology"].pop("braking-force-7"))
        self.assertFalse(lua.globals().final_ok)
        self.assertIn("MIR native continuation", str(lua.globals().final_error))
        self.assertEqual({}, _plain(lua.globals().emitted).get("technology", {}))

    def test_nondefault_py_stream_cost_time_and_effect_are_applied_after_preflight(self):
        rows = self._technology_rows(self.stage("q001", {
            "ips-cost-base-research_plastic": {"value": 300},
            "ips-cost-linear-increment-research_plastic": {"value": 10},
            "ips-cost-growth-research_plastic": {"value": 1.5},
            "ips-research-time-research_plastic": {"value": 40},
            "ips-effect-per-level-research_plastic": {"value": 17},
        }))
        plastic = rows["recipe-prod-research_plastic-1"]
        self.assertEqual("(300+10*(L-1))*1.5^(L-1)", plastic["unit"]["count_formula"])
        self.assertEqual(40, plastic["unit"]["time"])
        self.assertEqual([0.17] * 6, [effect["change"] for effect in plastic["effects"]])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PyF210PipelineTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
