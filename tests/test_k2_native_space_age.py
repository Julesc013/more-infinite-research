"""Independent F210 K2+Assets+Space Age data-final admission control.

The small context is projected only from the successful upstream q062 capture.
Its q013 carrier rows are a separate published migration expectation. The
published missing automation.png icon is repaired to the actual Base asset;
neither record is a MIR5 native qualification result.
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
CONTEXT_PATH = ROOT / "tests/fixtures/k2-native-space-age-f210-context.json.gz"
MAX_CONTEXT_BYTES = 512 * 1024
Q062_RAW_SHA256 = "7F823207953C1245EE11D72BB8BC8CA3378826C2F7935486BDAFA7BF8C12C5A7"
Q013_RAW_SHA256 = "95953A89CA8B03AEEB481219228DBBDC020EE1361CB0A646D39B8C99E5ABBCFC"
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
CARRIERS = {
    "mir-k2-imersite-staged-state-1",
    "mir-k2-imersite-continuation-state-4",
}
PUBLIC_IMERSITE = {
    "recipe-prod-research_material_imersite-1",
    "recipe-prod-research_material_imersite-4",
}
NATIVE_OWNERS = {
    "low-density-structure-productivity",
    "plastic-bar-productivity",
    "processing-unit-productivity",
    "rocket-fuel-productivity",
    "steel-plate-productivity",
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


def _active_mod_map(rows):
    return {row["name"]: row["version"] for row in rows if row["enabled"]}


class K2NativeSpaceAgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("K2+Space Age context exceeds its 512 KiB compressed bound")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        if cls.context.get("schema") != "MIR5K2NativeSpaceAgeF210ContextV1":
            raise AssertionError("K2+Space Age context schema changed")
        cls.raw = cls.context["raw"]
        cls.mods = _active_mod_map(cls.context["q062_upstream"]["active_mods"])

    def stage(self, *, startup=None, mods=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, deepcopy(self.raw))
        lua.globals().active_mods = _lua_value(lua, deepcopy(mods or self.mods))
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods = active_mods
          script = nil
          helpers = {}
          log = function() end
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

    def expected_legacy_carriers(self):
        rows = deepcopy(self.context["q013_published_imersite_carriers"]["technologies"])
        for row in rows.values():
            self.assertEqual("__base__/graphics/technology/automation.png", row["icon"])
            # Exact 2.1.23 Base has automation-1.png, not automation.png. A
            # headless prototype dump does not validate texture existence.
            row["icon"] = "__base__/graphics/technology/automation-1.png"
        return rows

    def _technology_rows(self, lua):
        return _plain(lua.globals().emitted).get("technology", {})

    def direct_modern_rows(self, mods, startup=None):
        """Exercise the K2+SE selector without substituting its raw pipeline.

        The independent SE pipeline control owns its full upstream context. This
        narrow assertion proves that the shared F210 K2-base branch retains the
        historical state carriers before that control applies science/prototype
        publication.
        """
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().active_mods = _lua_value(lua, deepcopy(mods))
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, helpers, log = active_mods, {}, function() end
          settings = {startup = startup_values}
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          direct_selection = require("compatibility.modern_catalogue").select(mods)
          direct_rows = require("research.modern").technologies(
            direct_selection, require("research.settings").resolve(settings.startup, helpers, log))
        ''')
        return _plain(lua.globals().direct_selection), {
            row["name"]: row for row in _plain(lua.globals().direct_rows)
        }

    def test_context_is_bounded_upstream_only_and_preserves_failure_identity(self):
        self.assertLessEqual(CONTEXT_PATH.stat().st_size, MAX_CONTEXT_BYTES)
        upstream = self.context["q062_upstream"]
        self.assertEqual("MIR5PrototypeCaptureV1", upstream["kind"])
        self.assertEqual("completed-data-stage-observation-only", upstream["status"])
        self.assertFalse(upstream["native_qualification"])
        self.assertEqual(F210_SHA256, upstream["engine"]["sha256"])
        self.assertEqual(Q062_RAW_SHA256, self.context["q062_upstream_raw"]["sha256"])
        self.assertIn("Krastorio2", self.mods)
        self.assertIn("Krastorio2Assets", self.mods)
        self.assertIn("space-age", self.mods)
        self.assertNotIn("Krastorio2-spaced-out", self.mods)
        self.assertNotIn("k2so-assets", self.mods)
        self.assertTrue(self.raw["recipe"])
        self.assertTrue(self.raw["technology"])
        self.assertTrue(self.raw["lab"])
        for failure_name, expected_archive in (("published_b6", "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"),
                                               ("candidate_ce116", "CE1165CAC174EDA4800EBECAAEF29FC2E071B2E7160CD98F799FE21C2F151F9B")):
            failure = self.context["q062_mir_failures"][failure_name]
            self.assertEqual("failed", failure["status"], failure_name)
            self.assertEqual("[mir441-process-exit] 1", failure["failure"], failure_name)
            self.assertEqual(expected_archive, failure["mir_archive"]["sha256"], failure_name)
        carrier = self.context["q013_published_imersite_carriers"]
        self.assertEqual(Q013_RAW_SHA256, carrier["raw"]["sha256"])
        self.assertEqual(CARRIERS, set(carrier["technologies"]))
        self.assertIn("upstream data-raw dump only", self.context["projection_rules"]["source"])
        self.assertIn("no candidate prototype dump", self.context["projection_rules"]["source"])
        self.assertIn("graphics", self.context["projection_rules"]["excluded"])
        self.assertIn("autoplace", self.context["projection_rules"]["excluded"])

    def test_f210_k2_space_age_uses_ordinary_binding_and_exact_hidden_carriers(self):
        lua = self.stage()
        selection = _plain(lua.execute('return require("compatibility.modern_catalogue").select(mods)'))
        self.assertEqual("space-age", selection["profile"])
        self.assertFalse(selection["k2_imersite"])
        self.assertTrue(selection["k2_imersite_carriers"])
        self.assertTrue(_plain(lua.execute('return require("compatibility.modern_catalogue").is_k2_base(mods)')))
        rows = self._technology_rows(lua)
        self.assertTrue(CARRIERS.issubset(rows))
        self.assertFalse(PUBLIC_IMERSITE & set(rows))
        expected = self.expected_legacy_carriers()
        for name in CARRIERS:
            self.assertEqual(expected[name], rows[name], name)
        self.assertIn("recipe-prod-research_agricultural_growth_speed-1", rows)
        self.assertIn("recipe-prod-research_spoilage_preservation-1", rows)
        self.assertIn("recipe-prod-research_gears-1", rows)
        self.assertGreater(_plain(lua.globals().publications), 0)

    def test_native_owner_preflight_uses_upstream_named_rows_without_default_mutation(self):
        original = {name: deepcopy(self.raw["technology"][name]) for name in NATIVE_OWNERS}
        lua = self.stage()
        final_raw = _plain(lua.globals().data)["raw"]["technology"]
        self.assertEqual(original, {name: final_raw[name] for name in NATIVE_OWNERS})
        configured = self.stage(startup={"ips-effect-per-level-research_steel": {"value": 17}})
        configured_raw = _plain(configured.globals().data)["raw"]["technology"]
        effects = configured_raw["steel-plate-productivity"]["effects"]
        self.assertEqual([0.17, 0.17], [row["change"] for row in effects])
        self.assertEqual(original["steel-plate-productivity"]["unit"],
                         configured_raw["steel-plate-productivity"]["unit"])

    def test_configured_legacy_carriers_reuse_k2so_cost_time_and_effect_authority(self):
        startup = {
            "ips-cost-base-research_material_imersite": {"value": 300},
            "ips-cost-linear-increment-research_material_imersite": {"value": 10},
            "ips-cost-growth-research_material_imersite": {"value": 1.5},
            "ips-research-time-research_material_imersite": {"value": 40},
            "ips-effect-per-level-research_material_imersite": {"value": 3.5},
        }
        rows = self._technology_rows(self.stage(startup=startup))
        early = rows["mir-k2-imersite-staged-state-1"]
        continuation = rows["mir-k2-imersite-continuation-state-4"]
        self.assertEqual("(300+10*(L-1))*1.5^(L-1)", early["unit"]["count_formula"])
        self.assertEqual("1113.75+300*(L-4)", continuation["unit"]["count_formula"])
        for row in (early, continuation):
            self.assertEqual(40, row["unit"]["time"])
            self.assertEqual([0.035], [effect["change"] for effect in row["effects"]])
            self.assertTrue(row["enabled"])
            self.assertTrue(row["hidden"])
            self.assertFalse(row["upgrade"])
            self.assertEqual([["automation-science-pack", 1]], row["unit"]["ingredients"])

    def test_k2_base_space_exploration_selection_retains_the_same_private_carriers(self):
        k2se = deepcopy(self.mods)
        k2se.pop("space-age")
        k2se["space-exploration"] = "0.7.63"
        selection, rows = self.direct_modern_rows(k2se)
        self.assertEqual("k2-space-exploration-f210", selection["profile"])
        self.assertFalse(selection["k2_imersite"])
        self.assertTrue(selection["k2_imersite_carriers"])
        self.assertEqual(
            self.expected_legacy_carriers(),
            {name: rows[name] for name in CARRIERS},
        )

    def test_partial_k2so_marker_refuses_before_technology_publication(self):
        partial = deepcopy(self.mods)
        partial["Krastorio2-spaced-out"] = "2.0.19"
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, deepcopy(self.raw))
        lua.globals().active_mods = _lua_value(lua, partial)
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
        self.assertFalse(lua.globals().final_ok)
        self.assertIn("unsupported partial K2SO selection", str(lua.globals().final_error))
        self.assertEqual({}, _plain(lua.globals().emitted).get("technology", {}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(K2NativeSpaceAgeTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
