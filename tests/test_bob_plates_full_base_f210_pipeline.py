"""Independent q005 full-Bob Base pipeline control for Bob Plates selection."""

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
CONTEXT_PATH = ROOT / "tests/fixtures/bob-plates-full-base-f210-upstream-context.json.gz"
MAX_CONTEXT_BYTES = 192 * 1024
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
UPSTREAM_RESULT_SHA256 = "F4225D5898019EB61A078B63378DB4C529B6FA6CA29109D4205EDEC81B930BC1"
UPSTREAM_RAW_SHA256 = "E50A66C38427AE45765564D301085BF42BC17FB904BAF93EB296C4CF4B648D6F"
PUBLISHED_RESULT_SHA256 = "2AAF8E6831993B6303A30E5EE32026B6C090C77C3D6EB8D0653B3CDEE5B27696"
PUBLISHED_RAW_SHA256 = "80462037B1982AF008B845D1389045C69E8D0BF58C0D7BC7A287BD4B4FC4024F"
B6_SHA256 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"

# Reuse the sparse Bob Plates conversion/contract helpers rather than creating
# a parallel Lua table adapter or a second public-row comparison convention.
sys.path.insert(0, str(ROOT / "tests"))
from test_bob_plates_f210_pipeline import _lua_value, _plain, _technology_contract  # noqa: E402


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


class BobPlatesFullBaseF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("full-Bob Base upstream context exceeds 192 KiB compressed")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        if cls.context.get("schema") != "MIR5BobPlatesFullBaseF210UpstreamContextV1":
            raise AssertionError("full-Bob Base context schema changed")
        cls.selection = {row["name"]: row["version"] for row in cls.context["selection"]}

    @staticmethod
    def _lua_target(lua):
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
        ''')

    def selector_result(self, mods):
        lua = LuaRuntime(unpack_returned_tuples=True)
        self._lua_target(lua)
        lua.globals().active_mods = _lua_value(lua, mods)
        return lua.execute('return require("compatibility.bob_plates_profile").select(active_mods)')

    def stage(self, raw_override=None, mods_override=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        self._lua_target(lua)
        lua.globals().captured_raw = _lua_value(lua, deepcopy(raw_override or self.context["raw"]))
        lua.globals().active_mods = _lua_value(lua, deepcopy(mods_override or self.selection))
        return lua.execute(r'''
          mods, script, helpers, log = active_mods, nil, {}, function() end
          data = {raw = captured_raw}
          setting_rows, emitted, technology_writes = {}, {}, 0
          function data:extend(rows)
            for _, row in ipairs(rows) do
              self.raw[row.type] = self.raw[row.type] or {}
              assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
              self.raw[row.type][row.name] = row
              if row.setting_type == "startup" then setting_rows[row.name] = row end
              if row.type == "technology" then emitted[row.name] = row; technology_writes = technology_writes + 1 end
            end
          end
          local constructor = require("compatibility.bob_plates_materials")
          local profile = constructor.preflight(captured_raw, active_mods)
          assert(loadfile(player_root .. "/settings.lua"))()
          local startup = {}
          for name, row in pairs(setting_rows) do startup[name] = {value = row.default_value} end
          settings = {startup = startup}
          assert(loadfile(player_root .. "/data.lua"))()
          assert(loadfile(player_root .. "/data-final-fixes.lua"))()
          return profile, emitted, technology_writes
        ''')

    def test_upstream_projection_and_b6_rows_are_independent_and_exactly_bound(self):
        self.assertEqual("q005", self.context["scope"]["case"])
        self.assertFalse(self.context["scope"]["claims"]["candidate_raw_used"])
        self.assertEqual(F210_SHA256, self.context["scope"]["engine"]["sha256"])
        self.assertEqual(UPSTREAM_RESULT_SHA256, self.context["upstream"]["result"]["sha256"])
        self.assertEqual(UPSTREAM_RAW_SHA256, self.context["upstream"]["data_raw"]["sha256"])
        self.assertEqual(PUBLISHED_RESULT_SHA256, self.context["published"]["result"]["sha256"])
        self.assertEqual(PUBLISHED_RAW_SHA256, self.context["published"]["data_raw"]["sha256"])
        self.assertEqual(B6_SHA256, self.context["published"]["mir_archive"]["sha256"])
        self.assertEqual(self.context["projection_counts"], {kind: len(rows) for kind, rows in self.context["raw"].items()})
        self.assertEqual(31, len(self.context["published_expected_rows"]))
        self.assertIn("bobelectronics", self.selection)
        self.assertIn("bobtech", self.selection)
        self.assertNotIn("space-age", self.selection)
        self.assertNotIn("angelssmelting", self.selection)

    def test_selector_admits_q005_but_keeps_angel_and_actual_bob_core_boundaries(self):
        self.assertEqual("base", self.selector_result(self.selection))

        missing_provider = deepcopy(self.selection)
        missing_provider.pop("bobplates")
        self.assertIsNone(self.selector_result(missing_provider))

        angel = deepcopy(self.selection)
        angel["angelssmelting"] = "2.1.1"
        self.assertIsNone(self.selector_result(angel))

        actual_core_overlap = deepcopy(self.selection)
        actual_core_overlap["space-age"] = "2.1.23"
        self.assertIsNone(self.selector_result(actual_core_overlap))

        no_core_owner = deepcopy(actual_core_overlap)
        no_core_owner.pop("bobtech")
        self.assertEqual("space-age", self.selector_result(no_core_owner))

    def test_q005_raw_preflight_and_full_pipeline_render_all_31_independent_b6_rows(self):
        profile, emitted, technology_writes = self.stage()
        emitted = _plain(emitted)
        expected = self.context["published_expected_rows"]
        restored = {name: emitted[name] for name in expected if name in emitted}
        self.assertEqual("base", profile)
        self.assertEqual(set(expected), set(restored))
        for name, published in expected.items():
            self.assertEqual(_technology_contract(published), _technology_contract(restored[name]), name)
        self.assertGreater(technology_writes, len(expected))

    def test_named_raw_route_drift_still_refuses_before_pipeline_publication(self):
        raw = deepcopy(self.context["raw"])
        raw["recipe"].pop("bob-aluminium-plate")
        lua = LuaRuntime(unpack_returned_tuples=True)
        self._lua_target(lua)
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, self.selection)
        ok, error = lua.execute(r'''
          local constructor = require("compatibility.bob_plates_materials")
          return pcall(function() constructor.preflight(captured_raw, active_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("bob-aluminium-plate changed", error)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobPlatesFullBaseF210PipelineTests)
    )
    raise SystemExit(not result.wasSuccessful())
