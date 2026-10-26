"""Independent q007/q008 Angel F210 publication over upstream-only context.

The context contains only pre-final upstream prototype data.  The B6 public
technology rows remain an external historical oracle in the captured-facts
fixture; no candidate dump, emitted candidate row, or Lua module replacement
is an input to this control.
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
CONTEXT_PATH = ROOT / "tests/fixtures/angel-f210-upstream-context.json.gz"
FACTS_PATH = ROOT / "tests/fixtures/angel-f210-captured-facts.json.gz"
MAX_CONTEXT_BYTES = 512 * 1024
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
UPSTREAM_RAW_SHA256 = {
    "base": "D046AFBEB236B50A437C1BCDB10A1596689F0645457F628D7F99E35F4F804E5D",
    "space_age": "1510ADA995ECA17E43BC81D010EECBB94E413B231526F9AE9E5B25C6CAE354C0",
}
UPSTREAM_RESULT_SHA256 = {
    "base": "E42C6B6CB1E90B633367B8CF73C61A91DF3D5C3434536BA41B20BD0CE7E8191A",
    "space_age": "01CB0E564309D1FDA289AB41722993F3EEC324E0464D20BBA3BC098C95FC4D07",
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
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(nested) for key, nested in values.items()}


def _technology_contract(row):
    """The complete public row contract independent B6 captures establish."""
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


class AngelF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT_PATH.stat().st_size > MAX_CONTEXT_BYTES:
            raise AssertionError("Angel F210 upstream context exceeds 512 KiB compressed")
        with gzip.open(CONTEXT_PATH, "rt", encoding="utf-8") as stream:
            cls.context = json.load(stream)
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        if cls.context.get("schema") != "MIR5AngelF210UpstreamPipelineContextV1":
            raise AssertionError("Angel F210 upstream context schema changed")
        if cls.facts.get("schema") != "MIR5AngelF210CapturedFactsV1":
            raise AssertionError("Angel F210 captured facts schema changed")

    def stage(self, case, startup_overrides=None, raw_override=None, mods_override=None):
        context = self.context["cases"][case]
        raw = deepcopy(raw_override if raw_override is not None else context["raw"])
        mods = deepcopy(mods_override if mods_override is not None else context["selection"])
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, mods)
        lua.globals().startup_overrides = _lua_value(lua, startup_overrides or {})
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, script, helpers, log = active_mods, nil, {}, function() end
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          data = {raw = captured_raw}; setting_rows, emitted, technology_writes = {}, {}, 0
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
        return self.facts["captures"][case]["published"]["technologies"]

    def _actual_rows(self, lua, case):
        emitted = _plain(lua.globals().emitted)
        raw = _plain(lua.globals().captured_raw)
        expected = self._expected_rows(case)
        return {
            name: emitted.get(name, raw["technology"].get(name))
            for name in expected
            if emitted.get(name, raw["technology"].get(name)) is not None
        }

    def _assert_prepublication_refusal(self, case, raw, expected):
        """Run the real stages and retain the no-publication boundary."""
        context = self.context["cases"][case]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, context["selection"])
        ok, error, writes = lua.execute(r'''
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
        self.assertIn(expected, error)
        self.assertEqual(0, writes)

    def test_context_is_bounded_upstream_only_and_binds_exact_r04_inputs(self):
        self.assertLessEqual(CONTEXT_PATH.stat().st_size, MAX_CONTEXT_BYTES)
        self.assertEqual(F210_SHA256, self.context["r04"]["engine_sha256"])
        self.assertEqual(
            "524425A246135ECAA957A472D1E70B87D96F21CD2164887E78D8CC0ED9693E85",
            self.context["r04"]["plan_sha256"],
        )
        self.assertIn("candidate", self.context["scope"])
        self.assertIn("candidate", " ".join(self.context["projection_rules"]["excluded"]))
        for case in ("base", "space_age"):
            with self.subTest(case=case):
                context = self.context["cases"][case]
                self.assertEqual(UPSTREAM_RAW_SHA256[case], context["source_data_raw_dump"]["sha256"])
                self.assertEqual(UPSTREAM_RESULT_SHA256[case], context["source_result"]["sha256"])
                self.assertEqual("MIR5PrototypeCaptureV1", context["source_result"]["kind"])
                self.assertEqual("completed-data-stage-observation-only", context["source_result"]["status"])
                self.assertEqual(
                    context["projection_counts"],
                    {kind: len(rows) for kind, rows in context["raw"].items()},
                )
                self.assertNotIn("more-infinite-research", context["selection"])
                self.assertIn("angelssmelting", context["selection"])
                self.assertIn("technology", context["raw"])
                self.assertIn("recipe", context["raw"])
        self.assertNotIn("space-age", self.context["cases"]["base"]["selection"])
        self.assertIn("space-age", self.context["cases"]["space_age"]["selection"])

    def test_full_settings_data_and_final_pipeline_matches_independent_b6_rows(self):
        for case, expected_count in (("base", 8), ("space_age", 8)):
            with self.subTest(case=case):
                lua = self.stage(case)
                expected = self._expected_rows(case)
                actual = self._actual_rows(lua, case)
                self.assertEqual(expected_count, len(expected))
                self.assertEqual(set(expected), set(actual))
                for name, published in expected.items():
                    self.assertEqual(_technology_contract(published), _technology_contract(actual[name]), name)
        # Space Age owns the native row already.  The pipeline must patch it
        # in place and not attempt a duplicate data:extend publication.
        space_age = self.stage("space_age")
        self.assertNotIn("steel-plate-productivity", _plain(space_age.globals().emitted))
        self.assertIn("steel-plate-productivity", _plain(space_age.globals().captured_raw)["technology"])

    def test_breeding_default_and_nondefault_tuning_are_named_and_local(self):
        default = self._actual_rows(self.stage("base"), "base")
        configured = self._actual_rows(self.stage("base", {
            "ips-cost-base-research_breeding": 250,
            "ips-cost-growth-research_breeding": 3,
            "ips-research-time-research_breeding": 45,
            "ips-effect-per-level-research_breeding": 25,
        }), "base")
        self.assertEqual(_technology_contract(self._expected_rows("base")["recipe-prod-research_breeding-1"]),
                         _technology_contract(default["recipe-prod-research_breeding-1"]))
        breeding = configured["recipe-prod-research_breeding-1"]
        self.assertEqual("250*3^(L-1)", breeding["unit"]["count_formula"])
        self.assertEqual(45, breeding["unit"]["time"])
        expected_effects = self._expected_rows("base")["recipe-prod-research_breeding-1"]["effects"]
        self.assertEqual([effect["recipe"] for effect in expected_effects],
                         [effect["recipe"] for effect in breeding["effects"]])
        self.assertEqual([0.25] * len(expected_effects),
                         [effect["change"] for effect in breeding["effects"]])
        self.assertEqual(default["recipe-prod-research_lubricant_productivity-1"],
                         configured["recipe-prod-research_lubricant_productivity-1"])

    def test_disabled_breeding_keeps_the_saved_identity_and_effect_contract(self):
        default = self._actual_rows(self.stage("base"), "base")
        disabled = self._actual_rows(self.stage("base", {
            "ips-enable-research_breeding": False,
        }), "base")
        name = "recipe-prod-research_breeding-1"
        self.assertEqual(default[name]["name"], disabled[name]["name"])
        self.assertEqual(default[name]["prerequisites"], disabled[name]["prerequisites"])
        self.assertEqual(default[name]["effects"], disabled[name]["effects"])
        self.assertEqual(default[name]["unit"], disabled[name]["unit"])
        self.assertFalse(disabled[name]["enabled"])

    def test_base_breeding_aluminium_and_research_speed_contracts_stay_distinct(self):
        rows = self._actual_rows(self.stage("base"), "base")
        self.assertEqual(
            ["angels-plate-aluminium", "angels-plate-aluminium-2"],
            [effect["recipe"] for effect in rows["recipe-prod-research_material_aluminium-1"]["effects"]],
        )
        self.assertIn("angels-gardens", rows["research-speed-7"]["prerequisites"])
        self.assertEqual(
            _technology_contract(self._expected_rows("base")["research-speed-7"]),
            _technology_contract(rows["research-speed-7"]),
        )

    def test_space_age_garden_science_and_native_steel_continuation_are_exact(self):
        rows = self._actual_rows(self.stage("space_age"), "space_age")
        self.assertIn("angels-gardens", rows["research-speed-7"]["prerequisites"])
        science = rows["recipe-prod-research_science_pack_productivity-1"]
        self.assertIn("angels-gardens", science["prerequisites"])
        self.assertIn("angels-token-bio", [ingredient[0] for ingredient in science["unit"]["ingredients"]])
        steel = rows["steel-plate-productivity"]
        upstream_steel = self.context["cases"]["space_age"]["raw"]["technology"]["steel-plate-productivity"]
        exception = self.context["projection_rules"]["full_native_owner_exceptions"]
        self.assertEqual(1, len(exception))
        self.assertEqual("steel-plate-productivity", exception[0]["name"])
        upstream_canonical = json.dumps(upstream_steel, sort_keys=True, separators=(",", ":")).encode("utf-8")
        self.assertEqual(exception[0]["source_row_sha256"], hashlib.sha256(upstream_canonical).hexdigest().upper())
        # The Space Age native owner exists before MIR.  B6 retains its unit,
        # prerequisites and existing effects while appending exactly the two
        # Angel steel routes; this is an in-place native-owner patch, never a
        # published-created prototype seeded into the upstream context.
        self.assertEqual(
            ["steel-plate", "casting-steel"],
            [effect["recipe"] for effect in upstream_steel["effects"]],
        )
        self.assertEqual(
            ["steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"],
            [effect["recipe"] for effect in steel["effects"]],
        )
        self.assertEqual(upstream_steel["unit"], steel["unit"])
        self.assertEqual(upstream_steel["prerequisites"], steel["prerequisites"])
        self.assertEqual("1.5^L*1000", steel["unit"]["count_formula"])
        self.assertEqual(60, steel["unit"]["time"])
        self.assertEqual(
            _technology_contract(self._expected_rows("space_age")["steel-plate-productivity"]),
            _technology_contract(steel),
        )

    def test_space_age_native_steel_nondefault_tuple_preserves_unowned_fields(self):
        raw = deepcopy(self.context["cases"]["space_age"]["raw"])
        steel_input = raw["technology"]["steel-plate-productivity"]
        steel_input["effects"].append({
            "type": "change-recipe-productivity",
            "recipe": "unrelated-valid-steel-route",
            "change": 0.1,
        })
        upstream_unit = deepcopy(steel_input["unit"])
        upstream_icons = deepcopy(steel_input["icons"])
        upstream_prerequisites = deepcopy(steel_input["prerequisites"])
        configured = self._actual_rows(self.stage("space_age", {
            "ips-cost-base-research_steel": 250,
            "ips-cost-linear-increment-research_steel": 3,
            "ips-cost-growth-research_steel": 1.5,
            "ips-research-time-research_steel": 45,
            "ips-effect-per-level-research_steel": 25,
        }, raw_override=raw), "space_age")["steel-plate-productivity"]
        self.assertEqual("(250+3*(L-1))*1.5^(L-1)", configured["unit"]["count_formula"])
        self.assertEqual(45, configured["unit"]["time"])
        self.assertEqual(upstream_unit["ingredients"], configured["unit"]["ingredients"])
        self.assertEqual(upstream_icons, configured["icons"])
        self.assertEqual(upstream_prerequisites, configured["prerequisites"])
        changes = {effect["recipe"]: effect["change"] for effect in configured["effects"]}
        self.assertEqual(0.25, changes.pop("steel-plate"))
        self.assertEqual(0.25, changes.pop("casting-steel"))
        self.assertEqual(0.25, changes.pop("angels-plate-steel"))
        self.assertEqual(0.25, changes.pop("angels-plate-steel-2"))
        self.assertEqual({"unrelated-valid-steel-route": 0.1}, changes)

    def test_disabled_native_steel_preserves_the_existing_owner_identity_and_effects(self):
        upstream = deepcopy(self.context["cases"]["space_age"]["raw"]["technology"]["steel-plate-productivity"])
        disabled = self._actual_rows(self.stage("space_age", {
            "ips-enable-research_steel": False,
        }), "space_age")["steel-plate-productivity"]
        self.assertEqual(upstream["name"], disabled["name"])
        self.assertEqual(upstream["unit"], disabled["unit"])
        self.assertEqual(upstream["icons"], disabled["icons"])
        self.assertEqual(upstream["prerequisites"], disabled["prerequisites"])
        self.assertEqual(upstream["effects"], disabled["effects"])

    def test_unexpected_preexisting_angel_steel_effect_refuses_before_publication(self):
        raw = deepcopy(self.context["cases"]["space_age"]["raw"])
        raw["technology"]["steel-plate-productivity"]["effects"].append({
            "type": "change-recipe-productivity",
            "recipe": "angels-plate-steel",
            "change": 0.1,
        })
        self._assert_prepublication_refusal(
            "space_age", raw, "missing or duplicate effect for angels-plate-steel"
        )

    def test_runtime_native_admission_and_base_aluminium_settings_expose_exact_routes(self):
        space_declared = {
            row["id"]: row for row in _plain(self.stage("space_age").globals().declared)
        }
        native = space_declared["steel-plate-productivity"]
        self.assertEqual("nativeowner", native["ownership_kind"])
        self.assertEqual("steel-plate-productivity", native["native_owner_identity"])
        self.assertEqual("change-recipe-productivity", native["native_admission"]["effect_type"])
        self.assertEqual(
            ["steel-plate", "casting-steel", "angels-plate-steel", "angels-plate-steel-2"],
            native["native_admission"]["recipes"],
        )

        base = self.stage("base")
        base_declared = {
            row["id"]: row for row in _plain(base.globals().declared)
        }
        settings = _plain(base.globals().setting_rows)
        for name, progression in (
            ("recipe-prod-research_material_aluminium-1", 1),
            ("recipe-prod-research_material_aluminium-4", 4),
        ):
            with self.subTest(name=name):
                row = base_declared[name]
                self.assertEqual("research_material_aluminium", row["family"])
                self.assertEqual(progression, row["progression"])
                self.assertEqual("ips-enable-research_material_aluminium", row["setting"])
                self.assertEqual("ips-max-level-research_material_aluminium", row["cap_setting"])
                self.assertEqual(["angels-plate-aluminium", "angels-plate-aluminium-2"],
                                 row["productivity_recipes"])
                for setting in row["settings"]:
                    self.assertIn(setting, settings)
                    self.assertFalse(settings[setting].get("hidden", False), setting)

    def test_named_route_or_native_owner_drift_refuses_before_technology_publication(self):
        for case, mutate, expected in (
            ("base", lambda raw: raw["recipe"].pop("angels-plate-aluminium"), "angels-plate-aluminium changed"),
            ("space_age", lambda raw: raw["technology"]["steel-plate-productivity"]["unit"].update({"count_formula": "wrong"}),
             "steel-plate-productivity changed"),
        ):
            with self.subTest(case=case):
                raw = deepcopy(self.context["cases"][case]["raw"])
                mutate(raw)
                self._assert_prepublication_refusal(case, raw, expected)

    def test_inactive_selection_is_lazy_and_does_not_need_angel_routes(self):
        raw = deepcopy(self.context["cases"]["base"]["raw"])
        raw["recipe"].pop("angels-plate-aluminium")
        mods = deepcopy(self.context["cases"]["base"]["selection"])
        mods.pop("angelssmelting")
        lua = self.stage("base", raw_override=raw, mods_override=mods)
        actual = _plain(lua.globals().emitted)
        # General productivity families can still be selected without Angel;
        # only the Angel-owned breeding and aluminium identities establish
        # this adapter's lazy boundary.
        self.assertNotIn("recipe-prod-research_breeding-1", actual)
        self.assertNotIn("recipe-prod-research_material_aluminium-1", actual)
        self.assertNotIn("recipe-prod-research_material_aluminium-4", actual)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AngelF210PipelineTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
