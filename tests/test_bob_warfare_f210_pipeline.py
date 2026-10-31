"""Independent F210 Bob Warfare armor/laser controls across six native inputs."""
import argparse
from copy import deepcopy
import gzip
import json
from pathlib import Path
import sys
import unittest

from test_space_exploration_pipeline import _lua_value, _plain

ROOT = Path(__file__).resolve().parents[1]
CONTEXT = ROOT / "tests/fixtures/bob-warfare-f210-upstream-context.json.gz"
CASES = {"q005", "q006", "q009", "q010", "q083", "q084"}
ENGINE = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
PUBLISHED = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"


def contract(row):
    fields = ("name", "type", "icons", "icon", "icon_size", "localised_name", "localised_description",
              "level", "max_level", "upgrade", "order", "unit", "prerequisites", "effects")
    output = {key: row[key] for key in fields if key in row}
    for key in ("prerequisites", "effects"):
        output[key] = output.get(key) or []
    output["enabled"], output["hidden"] = row.get("enabled", True), row.get("hidden", False)
    return output


class BobWarfareF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if CONTEXT.stat().st_size > 2 * 1024 * 1024:
            raise AssertionError("Bob Warfare context exceeds the 2 MiB compressed bound")
        cls.context = json.loads(gzip.decompress(CONTEXT.read_bytes()))

    def stage(self, case, startup=None, mutate=None, remove_provider=False, expect_failure=False):
        context = self.context["cases"][case]
        raw, mods = deepcopy(context["raw"]), deepcopy(context["selection"])
        if mutate:
            mutate(raw)
        if remove_provider:
            mods.pop("bobwarfare")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, mods)
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          package.path=player_root.."/?.lua;"..player_root.."/?/init.lua";package.cpath=""
          mods,script,helpers,log=active_mods,nil,{},function() end
          settings={startup=startup_values};emitted={};technology_publications=0;data={raw=captured_raw}
          function data:extend(rows)
            local technology=false
            for _,row in ipairs(rows) do
              self.raw[row.type]=self.raw[row.type] or {}
              assert(not self.raw[row.type][row.name],"duplicate "..row.type..":"..row.name)
              self.raw[row.type][row.name]=row
              if row.type=="technology" then emitted[row.name]=row;technology=true end
            end
            if technology then technology_publications=technology_publications+1 end
          end
          assert(loadfile(player_root.."/settings.lua"))()
          for _,spec in ipairs(require("research.settings").prototypes()) do
            if settings.startup[spec.name]==nil then settings.startup[spec.name]={value=spec.default_value} end
          end
          assert(loadfile(player_root.."/data.lua"))()
          emitted={};technology_publications=0
          outcome,message=pcall(function() assert(loadfile(player_root.."/data-final-fixes.lua"))() end)
        ''')
        if expect_failure:
            self.assertFalse(lua.globals().outcome)
        else:
            self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        return lua

    def test_inputs_are_independent_upstream_and_published_with_explicit_scope(self):
        self.assertEqual("MIR5BobWarfareF210PipelineContextV1", self.context["schema"])
        self.assertEqual(CASES, set(self.context["cases"]))
        for case, row in self.context["cases"].items():
            for arm in ("upstream", "published"):
                capture = row["provenance"][arm]
                self.assertEqual(ENGINE, capture["engine"]["sha256"])
                self.assertEqual("2.1.23", capture["engine"]["base_version"])
                self.assertRegex(capture["result_sha256"], r"^[A-F0-9]{64}$")
                self.assertRegex(capture["raw_sha256"], r"^[A-F0-9]{64}$")
                self.assertEqual("ea41cbc6d27626283db9d8bbf6211b2171b6e36a", capture["source_head"])
            self.assertIsNone(row["provenance"]["upstream"]["mir_archive"])
            self.assertEqual(PUBLISHED, row["provenance"]["published"]["mir_archive"]["sha256"])
            self.assertNotIn("candidate", row["provenance"])
            self.assertNotIn("sprite", row["raw"])
            self.assertNotIn("gui-style", row["raw"])
            self.assertEqual(case in {"q006", "q010", "q084"}, "space-age" in row["selection"])

    def test_complete_pipeline_matches_four_independent_affected_rows_in_all_six_cases(self):
        for case in sorted(CASES):
            with self.subTest(case=case):
                lua = self.stage(case)
                rows = _plain(lua.globals().emitted)
                for name, expected in self.context["cases"][case]["expected"].items():
                    self.assertEqual(contract(expected), contract(rows[name]), case + ":" + name)
                self.assertEqual(1, lua.globals().technology_publications)

    def test_nondefault_armor_and_both_laser_categories_retain_configured_authority(self):
        lua = self.stage("q005", startup={
            "ips-cost-base-research_armor_components": {"value": 300},
            "ips-cost-linear-increment-research_armor_components": {"value": 10},
            "ips-cost-growth-research_armor_components": {"value": 1.5},
            "ips-research-time-research_armor_components": {"value": 45},
            "ips-effect-per-level-research_armor_components": {"value": 8},
            "mir-effect-per-level-laser-shooting-speed": {"value": 75},
        })
        rows = _plain(lua.globals().emitted)
        armor = rows["recipe-prod-research_armor_components-1"]
        self.assertEqual("(300+10*(L-1))*1.5^(L-1)", armor["unit"]["count_formula"])
        self.assertEqual(45, armor["unit"]["time"])
        defaults = self.context["cases"]["q005"]["expected"][armor["name"]]["effects"]
        self.assertEqual([row["recipe"] for row in defaults], [row["recipe"] for row in armor["effects"]])
        for expected, actual in zip(defaults, armor["effects"]):
            self.assertAlmostEqual(expected["change"] * 8 / 5, actual["change"])
        laser = rows["laser-shooting-speed-8"]["effects"]
        self.assertEqual({"laser", "bob-laser-rifle"}, {effect["ammo_category"] for effect in laser})
        self.assertEqual([0.75, 0.75], [effect["modifier"] for effect in laser])

    def test_changed_plate_variant_and_native_predecessor_refuse_before_publication(self):
        def bad_plate(raw):
            raw["recipe"]["bob-mech-armor-plate"]["ingredients"][1]["name"] = "steel-plate"

        def bad_native(raw):
            raw["technology"]["laser-shooting-speed-7"]["unit"]["count"] += 1

        for mutate, message in ((bad_plate, "armor route changed"), (bad_native, "predecessor unit changed")):
            lua = self.stage("q005", mutate=mutate, expect_failure=True)
            self.assertIn(message, str(lua.globals().message))
            self.assertEqual(0, lua.globals().technology_publications)

    def test_absent_provider_does_not_import_armor_body(self):
        lua = self.stage("q083", remove_provider=True)
        self.assertIsNone(lua.execute('return package.loaded["compatibility.modern_catalogue.bob_warfare"]'))
        self.assertNotIn("recipe-prod-research_armor_components-1", _plain(lua.globals().emitted))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(BobWarfareF210PipelineTests))
    sys.exit(0 if result.wasSuccessful() else 1)
