"""Independent F210 Bob Plates publication over exact upstream-only contexts.

The compact context deliberately supplies upstream q097/q098 prototype fields.
Published rows remain an external historical oracle in the captured-facts file;
no candidate prototype dump is an input to this control.
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
CONTEXT_PATH = ROOT / "tests/fixtures/bob-plates-f210-upstream-context.json.gz"
FACTS_PATH = ROOT / "tests/fixtures/bob-plates-f210-captured-facts.json.gz"
MAX_CONTEXT_BYTES = 128 * 1024
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
UPSTREAM_RAW_SHA256 = {
    "q097": "ED44B652498FD1149A1DAA4992153D6CB5CAA73BDF19B897CB2630E91B7C4D67",
    "q098": "D5874F94AFEFB5E56185AE33678739D93CA9F51D5D36A30CB91AD56C18BE8C6E",
}
UPSTREAM_RESULT_SHA256 = {
    "q097": "FB4574840BBD890B8864574256450F11D7F77AFB94161A9C3E34A30FF2F93A26",
    "q098": "C44DE8A261719CF3C0176ACF20D4AB322043D1F740EB92118674265B552E15C3",
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
    """All meaningful public fields for the independent restored-row oracle."""
    return {
        "type": row["type"],
        "name": row["name"],
        "icon": row.get("icon"),
        "icon_size": row.get("icon_size"),
        "icons": row.get("icons"),
        "localised_name": row.get("localised_name"),
        "localised_description": row.get("localised_description"),
        "level": row.get("level"),
        "upgrade": row.get("upgrade"),
        "max_level": row.get("max_level"),
        "order": row.get("order"),
        "enabled": row.get("enabled", True),
        "visible_when_disabled": row.get("visible_when_disabled"),
        "prerequisites": row.get("prerequisites", []),
        "effects": row.get("effects", []),
        "unit": row.get("unit"),
    }


class BobPlatesF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("Bob Plates upstream pipeline context exceeds 128 KiB compressed")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        if cls.context.get("schema") != "MIR5BobPlatesF210UpstreamPipelineContextV1":
            raise AssertionError("Bob Plates upstream pipeline context schema changed")
        if cls.facts.get("schema") != "MIR5BobPlatesF210CapturedFactsV1":
            raise AssertionError("Bob Plates published facts schema changed")

    def stage(self, case, startup_overrides=None, raw_override=None, mods_override=None):
        context = self.context["cases"][case]
        raw = deepcopy(raw_override if raw_override is not None else context["raw"])
        mods = deepcopy(mods_override if mods_override is not None else {
            row["name"]: row["version"] for row in context["selection"]
        })
        startup_overrides = startup_overrides or {}
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, mods)
        lua.globals().startup_overrides = _lua_value(lua, startup_overrides)
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, script, helpers, log = active_mods, nil, {}, function() end
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          data = {raw = captured_raw}
          setting_rows, emitted, technology_writes = {}, {}, 0
          function data:extend(rows)
            for _, row in ipairs(rows) do
              self.raw[row.type] = self.raw[row.type] or {}
              assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
              self.raw[row.type][row.name] = row
              if row.setting_type == "startup" then setting_rows[row.name] = row end
              if row.type == "technology" then
                technology_writes = technology_writes + 1
                emitted[row.name] = row
              end
            end
          end
          assert(loadfile(player_root .. "/settings.lua"))()
          local startup = {}
          for name, row in pairs(setting_rows) do startup[name] = {value = row.default_value} end
          for name, value in pairs(startup_overrides) do
            assert(startup[name] ~= nil, "unknown startup override " .. tostring(name))
            startup[name] = {value = value}
          end
          settings = {startup = startup}
          assert(loadfile(player_root .. "/data.lua"))()
          assert(loadfile(player_root .. "/data-final-fixes.lua"))()
          declared = require("research.catalogue").declared()
        ''')
        return lua

    def _expected_rows(self, case):
        return self.facts["cases"][case]["published_rows"]

    def _restored_rows(self, lua, case):
        emitted = _plain(lua.globals().emitted)
        expected = self._expected_rows(case)
        return {name: emitted[name] for name in expected if name in emitted}

    def test_upstream_only_context_has_exact_receipt_selection_and_bounded_projection(self):
        self.assertLessEqual(CONTEXT_PATH.stat().st_size, MAX_CONTEXT_BYTES)
        self.assertEqual(F210_SHA256, self.context["scope"]["engine"]["sha256"])
        self.assertFalse(self.context["scope"]["claims"]["candidate_raw_used"])
        self.assertIn("candidate raw", self.context["projection_rules"]["excludes"])
        self.assertEqual(
            "tests/fixtures/bob-plates-f210-captured-facts.json.gz only",
            self.context["projection_rules"]["published_expectations"],
        )
        for case in ("q097", "q098"):
            with self.subTest(case=case):
                context = self.context["cases"][case]
                self.assertEqual(UPSTREAM_RAW_SHA256[case], context["source_data_raw_dump"]["sha256"])
                self.assertEqual(UPSTREAM_RESULT_SHA256[case], context["source_result"]["sha256"])
                self.assertEqual("MIR5PrototypeCaptureV1", context["source_result"]["kind"])
                self.assertEqual("completed-data-stage-observation-only", context["source_result"]["status"])
                self.assertEqual(context["projection_counts"], {
                    kind: len(rows) for kind, rows in context["raw"].items()
                })
                selected = {row["name"]: row["version"] for row in context["selection"]}
                self.assertEqual("3.0.2", selected["bobplates"])
                self.assertNotIn("more-infinite-research", selected)
                self.assertNotIn("bobelectronics", selected)
                self.assertNotIn("bobtech", selected)
        self.assertNotIn("space-age", {row["name"] for row in self.context["cases"]["q097"]["selection"]})
        self.assertIn("space-age", {row["name"] for row in self.context["cases"]["q098"]["selection"]})

    def test_full_settings_data_and_final_pipeline_matches_all_independent_restored_rows(self):
        for case, expected_count in (("q097", 31), ("q098", 16)):
            with self.subTest(case=case):
                lua = self.stage(case)
                restored = self._restored_rows(lua, case)
                expected = self._expected_rows(case)
                self.assertEqual(expected_count, len(expected))
                self.assertEqual(set(expected), set(restored), case)
                for name, published in expected.items():
                    self.assertEqual(_technology_contract(published), _technology_contract(restored[name]), name)

    def test_default_settings_are_current_declarations_and_nondefault_material_tuning_changes_only_the_named_stream(self):
        default = self._restored_rows(self.stage("q097"), "q097")
        configured = self._restored_rows(self.stage("q097", {
            "ips-cost-base-research_material_bronze": 250,
            "ips-cost-linear-increment-research_material_bronze": 3,
            "ips-cost-growth-research_material_bronze": 1.5,
            "ips-research-time-research_material_bronze": 45,
            "ips-effect-per-level-research_material_bronze": 3,
        }), "q097")
        self.assertEqual(_technology_contract(self._expected_rows("q097")["recipe-prod-research_material_bronze-1"]),
                         _technology_contract(default["recipe-prod-research_material_bronze-1"]))
        early = configured["recipe-prod-research_material_bronze-1"]
        tail = configured["recipe-prod-research_material_bronze-4"]
        self.assertEqual("(250+3*(L-1))*1.5^(L-1)", early["unit"]["count_formula"])
        self.assertEqual(45, early["unit"]["time"])
        self.assertEqual([0.03], [effect["change"] for effect in tail["effects"]])
        self.assertEqual(default["recipe-prod-research_material_tin-1"], configured["recipe-prod-research_material_tin-1"])

    def test_restored_rows_have_runtime_cap_routes_and_visible_historical_settings(self):
        prefixes = ("ips-enable-", "ips-cost-base-", "ips-cost-linear-increment-",
                    "ips-cost-growth-", "ips-max-level-", "ips-research-time-", "ips-effect-per-level-")
        for case in ("q097", "q098"):
            with self.subTest(case=case):
                lua = self.stage(case)
                # Exercise control parsing, where Library/cap metadata is cached,
                # with a fresh module rather than a data-stage require result.
                lua.execute('''
                  script = {active_mods = mods}
                  package.loaded["research.catalogue"] = nil
                  runtime_declared = require("research.catalogue").declared()
                ''')
                declared = _plain(lua.globals().runtime_declared)
                settings_rows = _plain(lua.globals().setting_rows)
                for name, published in self._expected_rows(case).items():
                    matches = [row for row in declared if row["id"] == name]
                    self.assertEqual(1, len(matches), name)
                    row = matches[0]
                    family = name.removeprefix("recipe-prod-").rsplit("-", 1)[0]
                    self.assertEqual(family, row["family"], name)
                    self.assertEqual("ips-enable-" + family, row["setting"], name)
                    self.assertEqual("ips-max-level-" + family, row["cap_setting"], name)
                    self.assertEqual(list(prefix + family for prefix in prefixes), row["settings"], name)
                    self.assertEqual(published.get("level", 1), row["progression"], name)
                    for setting in row["settings"]:
                        self.assertIn(setting, settings_rows, name)
                        self.assertFalse(settings_rows[setting].get("hidden", False), setting)
                    if "_material_" in name:
                        self.assertEqual(3, row["productivity_ceiling"], name)
                        self.assertEqual([effect["recipe"] for effect in published["effects"]],
                                         row["productivity_recipes"], name)
    def test_disabled_material_keeps_the_exact_identity(self):
        default = self._restored_rows(self.stage("q097"), "q097")
        disabled = self._restored_rows(self.stage("q097", {
            "ips-enable-research_material_lead": False,
        }), "q097")
        self.assertEqual(set(default), set(disabled))
        for name in ("recipe-prod-research_material_lead-1", "recipe-prod-research_material_lead-4"):
            with self.subTest(name=name):
                self.assertEqual(default[name]["name"], disabled[name]["name"])
                self.assertEqual(default[name]["prerequisites"], disabled[name]["prerequisites"])
                self.assertEqual(default[name]["effects"], disabled[name]["effects"])
                self.assertEqual(default[name]["unit"], disabled[name]["unit"])
                self.assertFalse(disabled[name]["enabled"])
        self.assertEqual(default["recipe-prod-research_material_tin-1"], disabled["recipe-prod-research_material_tin-1"])

    def test_runtime_descriptors_name_every_published_identity_and_bounded_lead_routes(self):
        for case, expected_count in (("q097", 31), ("q098", 16)):
            with self.subTest(case=case):
                rows = _plain(self.stage(case).globals().declared)
                declared = {row["id"]: row for row in rows}
                expected = self._expected_rows(case)
                self.assertEqual(len(rows), len(declared))
                self.assertEqual(expected_count, len(expected))
                self.assertEqual(set(expected), set(expected) & set(declared))

        declared = {row["id"]: row for row in _plain(self.stage("q097").globals().declared)}
        for identifier, progression in (
            ("recipe-prod-research_material_lead-1", 1),
            ("recipe-prod-research_material_lead-4", 4),
        ):
            with self.subTest(identifier=identifier):
                descriptor = declared[identifier]
                self.assertEqual("research_material_lead", descriptor["family"])
                self.assertEqual(progression, descriptor["progression"])
                self.assertEqual("ips-enable-research_material_lead", descriptor["setting"])
                self.assertEqual("ips-max-level-research_material_lead", descriptor["cap_setting"])
                self.assertEqual(3, descriptor["productivity_ceiling"])
                self.assertEqual(["bob-lead-plate", "bob-lead-plate-2"], descriptor["productivity_recipes"])

    def test_inactive_sparse_selection_is_lazy_and_does_not_require_named_bob_plates_routes(self):
        raw = deepcopy(self.context["cases"]["q097"]["raw"])
        raw["recipe"].pop("bob-aluminium-plate")
        mods = {row["name"]: row["version"] for row in self.context["cases"]["q097"]["selection"]}
        mods.pop("bobplates")
        lua = self.stage("q097", raw_override=raw, mods_override=mods)
        emitted = _plain(lua.globals().emitted)
        self.assertTrue(set(self._expected_rows("q097")).isdisjoint(emitted), emitted.keys())

    def test_named_route_drift_refuses_before_any_technology_publication(self):
        for case, route in (("q097", "bob-aluminium-plate"), ("q098", "bob-gold-plate")):
            with self.subTest(case=case, route=route):
                raw = deepcopy(self.context["cases"][case]["raw"])
                raw["recipe"].pop(route)
                context = self.context["cases"][case]
                lua = LuaRuntime(unpack_returned_tuples=True)
                lua.globals().player_root = SOURCE_ROOT.as_posix()
                lua.globals().captured_raw = _lua_value(lua, raw)
                lua.globals().active_mods = _lua_value(lua, {
                    row["name"]: row["version"] for row in context["selection"]
                })
                ok, error, technology_writes = lua.execute(r'''
                  package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
                  package.cpath = ""
                  mods, script, helpers, log = active_mods, nil, {}, function() end
                  local target = require("platform.target")
                  target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
                  target.distribution_version, target.cargo_research = "5.0.21000", true
                  target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
                  data = {raw = captured_raw}; setting_rows, technology_writes = {}, 0
                  function data:extend(rows)
                    for _, row in ipairs(rows) do
                      self.raw[row.type] = self.raw[row.type] or {}
                      assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
                      self.raw[row.type][row.name] = row
                      if row.setting_type == "startup" then setting_rows[row.name] = row end
                      if row.type == "technology" then technology_writes = technology_writes + 1 end
                    end
                  end
                  assert(loadfile(player_root .. "/settings.lua"))()
                  local startup = {}
                  for name, row in pairs(setting_rows) do startup[name] = {value = row.default_value} end
                  settings = {startup = startup}
                  local ok, error = pcall(function()
                    assert(loadfile(player_root .. "/data.lua"))()
                    assert(loadfile(player_root .. "/data-final-fixes.lua"))()
                  end)
                  return ok, tostring(error), technology_writes
                ''')
                self.assertFalse(ok)
                self.assertIn(route + " changed", error)
                self.assertEqual(0, technology_writes)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobPlatesF210PipelineTests)
    )
    raise SystemExit(not result.wasSuccessful())
