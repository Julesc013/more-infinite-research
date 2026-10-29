"""Independent Ironclad mortar continuation and central F210 pipeline controls."""

import argparse
from copy import deepcopy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source"
CONTEXT = ROOT / "tests/fixtures/ironclad-f210-upstream-context.json.gz"
F200_INPUTS = ROOT / "tests/fixtures/bob-angel-f200-catalogue-inputs.json"
F200_PROFILE = ROOT / "tests/profiles/bob-angel-f200-2077.json"
ENGINE = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
B6 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
sys.path.insert(0, str(ROOT / "tests"))
from test_bob_plates_f210_pipeline import _lua_value, _plain  # noqa: E402


def contract(row):
    return {key: row.get(key) for key in (
        "name", "effects", "unit", "prerequisites", "icons", "localised_name",
        "localised_description", "level", "max_level", "hidden", "upgrade",
    )}


class IroncladF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT.stat().st_size > 128 * 1024:
            raise AssertionError("Ironclad context exceeds its bounded projection")
        if hashlib.sha256(CONTEXT.read_bytes()).hexdigest().upper() != "0BAC0313AA44BF3F65597614D835FEEEC6DF0E122CE492A77F28E309F5F9BC08":
            raise AssertionError("Ironclad independently captured context changed")
        cls.context = json.loads(gzip.decompress(CONTEXT.read_bytes()))

    def lua(self, target_id="f210"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE.as_posix()
        lua.globals().selected_target = target_id
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          local target = require("platform.target")
          if selected_target == "f210" then
            target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
            target.distribution_version, target.cargo_research = "5.0.21000", true
            target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          elseif selected_target == "f200" then
            target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
            target.distribution_version, target.cargo_research = "5.0.20000", false
            target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "probability", false, true
          else
            error("unsupported Ironclad test target")
          end
        ''')
        return lua

    def stage_raw(self, raw, active_mods, target_id, startup=None, mutate=None):
        raw = deepcopy(raw)
        if mutate is not None:
            mutate(raw)
        lua = self.lua(target_id)
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, deepcopy(active_mods))
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          mods, script, helpers, log = active_mods, nil, {}, function() end
          settings = {startup = startup_values}
          data = {raw = captured_raw}
          emitted, publications = {}, 0
          function data:extend(rows)
            local technology = false
            for _, row in ipairs(rows) do
              self.raw[row.type] = self.raw[row.type] or {}
              assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
              self.raw[row.type][row.name] = row
              if row.type == "technology" then emitted[row.name] = row; technology = true end
            end
            if technology then publications = publications + 1 end
          end
          assert(loadfile(player_root .. "/settings.lua"))()
          local declared_settings = {}
          for _, kind in ipairs({"bool-setting", "int-setting", "double-setting", "string-setting"}) do
            for name in pairs(data.raw[kind] or {}) do declared_settings[name] = true end
          end
          for name in pairs(startup_values) do assert(declared_settings[name], "unknown startup setting " .. name) end
          for _, spec in ipairs(require("research.settings").prototypes()) do
            if settings.startup[spec.name] == nil then settings.startup[spec.name] = {value = spec.default_value} end
          end
          assert(loadfile(player_root .. "/data.lua"))()
          emitted, publications = {}, 0
          outcome, message = pcall(function() assert(loadfile(player_root .. "/data-final-fixes.lua"))() end)
        ''')
        return lua

    def stage(self, case_id, startup=None, mutate=None):
        case = self.context["cases"][case_id]
        return self.stage_raw(case["raw"], case["selection"], "f210", startup, mutate)

    def test_context_pins_independent_upstream_b6_and_provider_facts(self):
        self.assertEqual("MIR5IroncladF210UpstreamContextV1", self.context["schema"])
        self.assertEqual({"q117", "q118"}, set(self.context["cases"]))
        self.assertFalse(self.context["scope"]["candidate_raw_used"])
        self.assertFalse(self.context["scope"]["native_qualification"])
        self.assertEqual("FF7417F20D40CA9496BD7074372B481360A8A756F02C448BC60B2AF17D09CA37",
                         self.context["provider"]["sha256"])
        expected = {
            "q117": ("3483F72C24E4A8A04256BF8AD5CBE03A91F55A3590D68B77F2BCEE322CC39491",
                     "D9EF377A4709F6AE03250DC8CCBB3F6C6EF6F67CCB7E0D5AB2ABA67DF38DB8F4"),
            "q118": ("F77F6640040EE7BEDDDDDADAB077834D01895047E609F93C3CDE775BB2B7127B",
                     "D4557AE53EFCA8C679BCD203AE652115ACBA3E92BBF2D609F1ADE7EE3E1E2E66"),
        }
        for case_id, (upstream, published) in expected.items():
            case = self.context["cases"][case_id]
            self.assertEqual(upstream, case["provenance"]["upstream"]["raw_sha256"])
            self.assertEqual(published, case["provenance"]["published"]["raw_sha256"])
            for arm in ("upstream", "published"):
                self.assertEqual(ENGINE, case["provenance"][arm]["engine"]["sha256"])
                self.assertTrue(case["provenance"][arm]["library_controls_restored"])
            self.assertIsNone(case["provenance"]["upstream"]["mir_archive"])
            self.assertEqual(B6, case["provenance"]["published"]["mir_archive"]["sha256"])

    def test_complete_base_and_space_age_pipeline_matches_independent_b6_continuation(self):
        for case_id in ("q117", "q118"):
            with self.subTest(case=case_id):
                lua = self.stage(case_id)
                self.assertTrue(lua.globals().outcome, str(lua.globals().message))
                row = _plain(lua.globals().emitted)["weapon-shooting-speed-7"]
                expected = self.context["cases"][case_id]["expected"][row["name"]]
                self.assertEqual(contract(expected), contract(row))
                self.assertEqual(1, lua.globals().publications)

    def test_configured_effect_cost_time_and_disabled_identity_keep_native_mortar_ratio(self):
        lua = self.stage("q118", startup={
            "mir-effect-per-level-weapon-shooting-speed": {"value": 25},
            "mir-cost-base-weapon-shooting-speed": {"value": 300},
            "mir-cost-growth-weapon-shooting-speed": {"value": 2},
            "mir-research-time-weapon-shooting-speed": {"value": 45},
        })
        self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        row = _plain(lua.globals().emitted)["weapon-shooting-speed-7"]
        self.assertEqual([0.25, 0.25, 0.8125], [effect["modifier"] for effect in row["effects"]])
        self.assertEqual(45, row["unit"]["time"])
        self.assertEqual("19200*2^(L-7)", row["unit"]["count_formula"])
        disabled = self.stage("q117", startup={"mir-enable-weapon-shooting-speed": {"value": False}})
        self.assertTrue(disabled.globals().outcome, str(disabled.globals().message))
        row = _plain(disabled.globals().emitted)["weapon-shooting-speed-7"]
        self.assertFalse(row["enabled"])
        self.assertEqual([0.4, 0.4, 1.3], [effect["modifier"] for effect in row["effects"]])

    def test_overlap_off_or_disabled_dedicated_streams_preserve_all_five_native_categories(self):
        for startup in (
            {"mir-adjust-vanilla-weapon-speed-techs": {"value": "off"}},
            {"ips-enable-research_rocket_shooting_speed": {"value": False},
             "ips-enable-research_cannon_shooting_speed": {"value": False}},
        ):
            with self.subTest(startup=startup):
                lua = self.stage("q117", startup=startup)
                self.assertTrue(lua.globals().outcome, str(lua.globals().message))
                row = _plain(lua.globals().emitted)["weapon-shooting-speed-7"]
                native = self.context["cases"]["q117"]["raw"]["technology"]["weapon-shooting-speed-6"]["effects"]
                self.assertEqual(native, row["effects"])

    def test_f200_real_bob_angel_raw_final_stage_preserves_native_categories_outside_default_overlap(self):
        """The helper applies to both modern engines; exercise F200 through final data stage."""
        inputs = json.loads(F200_INPUTS.read_text(encoding="utf-8"))
        profile = json.loads(F200_PROFILE.read_text(encoding="utf-8"))
        mods = {row["name"]: row["version"] for row in profile["mods"] if row["enabled"]}
        native = inputs["raw"]["technology"]["weapon-shooting-speed-6"]["effects"]
        native_by_category = {effect.get("ammo_category"): effect.get("modifier") for effect in native
                              if effect.get("type") == "gun-speed"}
        self.assertTrue({"bullet", "shotgun-shell", "cannon-shell", "rocket"}.issubset(native_by_category))
        self.assertEqual(0.4, native_by_category["bullet"])
        self.assertEqual(0.4, native_by_category["shotgun-shell"])

        default = self.stage_raw(inputs["raw"], mods, "f200")
        self.assertTrue(default.globals().outcome, str(default.globals().message))
        default_effects = {effect.get("ammo_category"): effect.get("modifier") for effect in
                           _plain(default.globals().emitted)["weapon-shooting-speed-7"]["effects"]
                           if effect.get("type") == "gun-speed"}
        self.assertEqual(0.4, default_effects["bullet"])
        self.assertEqual(0.4, default_effects["shotgun-shell"])
        self.assertNotIn("cannon-shell", default_effects)
        self.assertNotIn("rocket", default_effects)

        for startup in (
            {"mir-adjust-vanilla-weapon-speed-techs": {"value": "off"}},
            {"ips-enable-research_rocket_shooting_speed": {"value": False},
             "ips-enable-research_cannon_shooting_speed": {"value": False}},
        ):
            with self.subTest(startup=startup):
                lua = self.stage_raw(inputs["raw"], mods, "f200", startup)
                self.assertTrue(lua.globals().outcome, str(lua.globals().message))
                effects = {effect.get("ammo_category"): effect.get("modifier") for effect in
                           _plain(lua.globals().emitted)["weapon-shooting-speed-7"]["effects"]
                           if effect.get("type") == "gun-speed"}
                for category in ("bullet", "shotgun-shell", "cannon-shell", "rocket"):
                    self.assertEqual(native_by_category[category], effects[category])

    def test_missing_category_or_changed_native_mortar_refuses_before_publication(self):
        def missing_category(raw):
            raw["ammo-category"].pop("mortar-bomb")

        def changed_bonus(raw):
            for effect in raw["technology"]["weapon-shooting-speed-6"]["effects"]:
                if effect.get("ammo_category") == "mortar-bomb":
                    effect["modifier"] = 1.4

        def duplicate_bonus(raw):
            raw["technology"]["weapon-shooting-speed-6"]["effects"].append(
                {"type": "gun-speed", "ammo_category": "mortar-bomb", "modifier": 1.3})

        for mutate in (missing_category, changed_bonus, duplicate_bonus):
            with self.subTest(mutation=mutate.__name__):
                lua = self.stage("q117", mutate=mutate)
                self.assertFalse(lua.globals().outcome)
                self.assertIn("MIR Ironclad", str(lua.globals().message))
                self.assertEqual(0, lua.globals().publications)

    def test_binding_is_read_only_fresh_and_ignores_unconsumed_foreign_fields(self):
        raw = deepcopy(self.context["cases"]["q117"]["raw"])
        raw["technology"]["weapon-shooting-speed-6"]["foreign_marker"] = {"value": "retained"}
        raw["technology"]["weapon-shooting-speed-6"]["effects"].append(
            {"type": "nothing", "effect_description": "unrelated"})
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, raw)
        before = deepcopy(raw)
        lua.execute(r'''
          local module = require("compatibility.ironclad")
          module.preflight(captured_raw)
          local first = module.continuation_effect()
          first.scale = 99
          fresh_scale = module.continuation_effect().scale
        ''')
        self.assertEqual(before, _plain(lua.globals().captured_raw))
        self.assertEqual(3.25, lua.globals().fresh_scale)

    def test_no_provider_and_f200_keep_their_existing_continuation_surface(self):
        for target_id, active in (("f210", {"base": "2.1.23"}),
                                  ("f200", {"base": "2.0.77", "aai-vehicles-ironclad": "0.8.0"})):
            lua = self.lua()
            lua.globals().selected_target = target_id
            lua.globals().active_mods = _lua_value(lua, active)
            rows = lua.execute(r'''
              local target = require("platform.target")
              target.id = selected_target
              if selected_target == "f200" then
                target.factorio_version, target.minimum_base, target.cargo_research = "2.0", "2.0.77", false
              end
              local catalogue = require("compatibility.modern_catalogue")
              assert(not catalogue.is_ironclad(active_mods))
              return catalogue.continuations(active_mods)
            ''')
            weapon = next(row for row in _plain(rows) if row["id"] == "weapon-shooting-speed-7")
            self.assertEqual(["bullet", "shotgun-shell"], [effect["ammo_category"] for effect in weapon["effects"]])
            self.assertIsNone(lua.globals().package.loaded["compatibility.ironclad"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(IroncladF210PipelineTests))
    raise SystemExit(not result.wasSuccessful())
