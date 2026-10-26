"""Independent F210 Bob Plates Base/Space Age construction control.

Expected rows and all direct route ownership facts come from the completed
q097/q098 upstream and published captures.  The CE116 absence records remain
historical scope and are not used as an implementation oracle.
"""

import argparse
from copy import deepcopy
import gzip
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source"
FACTS_PATH = ROOT / "tests/fixtures/bob-plates-f210-captured-facts.json.gz"
MAX_FACTS_BYTES = 256 * 1024
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"


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


def _mod_map(selection):
    return {entry["name"]: entry["version"] for entry in selection}


def _stream_values(keys):
    return {
        "streams": {
            key: {
                "enabled": True,
                "base_cost": 200,
                "linear_increment": 0,
                "growth_factor": 2,
                "max_level": 0,
                "research_time": 30,
                "effect_percent": 2,
            }
            for key in keys
        },
        "options": {},
    }


def _product_stream_values(keys):
    values = _stream_values(())
    values["streams"] = {
        key: {
            "enabled": True,
            "base_cost": 8000,
            "linear_increment": 0,
            "growth_factor": 2,
            "max_level": 0,
            "research_time": 60,
            "effect_percent": 10,
        }
        for key in keys
    }
    return values


class BobPlatesF210MaterialsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if FACTS_PATH.stat().st_size > MAX_FACTS_BYTES:
            raise AssertionError("Bob Plates F210 facts exceed their 256 KiB compressed ceiling")
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        if cls.facts.get("schema") != "MIR5BobPlatesF210CapturedFactsV1":
            raise AssertionError("Bob Plates F210 facts schema changed")
        if cls.facts["scope"]["engine"]["sha256"] != F210_SHA256:
            raise AssertionError("Bob Plates facts engine changed")

    def raw_from_context(self, case):
        facts = self.facts["cases"][case]
        raw = {"item": deepcopy(facts["upstream_context"]["items"]), "recipe": {}, "technology": {}}
        for recipe, contract in facts["upstream_context"]["routes"].items():
            raw["recipe"][recipe] = deepcopy(contract["recipe"])
            for owner in contract["unlock_owners"]:
                target = raw["technology"].setdefault(owner["name"], {
                    "enabled": owner["enabled"],
                    "prerequisites": deepcopy(owner["prerequisites"]),
                    "unit": deepcopy(owner["unit"]),
                    "effects": [],
                })
                self.assertEqual(owner["enabled"], target["enabled"], owner["name"])
                self.assertEqual(owner["prerequisites"], target["prerequisites"], owner["name"])
                self.assertEqual(owner["unit"], target["unit"], owner["name"])
                target["effects"].extend(deepcopy(owner["matching_unlock_effects"]))
        for row in facts["published_rows"].values():
            for prerequisite in row["prerequisites"]:
                raw["technology"].setdefault(prerequisite, {})
        return raw

    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          mods, script, helpers, log = {}, nil, {}, function() end
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
          bob_plates_data = require("research.bob_plates_materials")
          bob_plates = require("compatibility.bob_plates_materials")
          modern = require("research.modern")
        ''')
        return lua

    def technologies(self, case, values=None, raw=None, mods=None):
        lua = self.lua()
        facts = self.facts["cases"][case]
        default_defs = _plain(lua.globals().bob_plates_data.material_definitions(case == "q097" and "base" or "space-age"))
        lua.globals().captured_raw = _lua_value(lua, raw or self.raw_from_context(case))
        lua.globals().captured_values = _lua_value(lua, values or _stream_values(row["key"] for row in default_defs))
        lua.globals().captured_mods = _lua_value(lua, mods or _mod_map(facts["profile"]["selection_without_mir"]))
        rows = _plain(lua.execute("return bob_plates.technologies(captured_values, captured_raw, captured_mods)"))
        return lua, {row["name"]: row for row in rows}

    def test_independent_capture_scope_and_profile_selection_are_exact(self):
        self.assertLessEqual(FACTS_PATH.stat().st_size, MAX_FACTS_BYTES)
        self.assertFalse(self.facts["scope"]["claims"]["native_qualification"])
        self.assertIn("candidate-derived expectations", self.facts["projection_rules"]["excludes"])
        for case, expected_profile in (("q097", "base"), ("q098", "space-age")):
            facts = self.facts["cases"][case]
            self.assertEqual("completed-data-stage-observation-only", facts["arms"]["upstream"]["status"])
            self.assertEqual("completed-data-stage-observation-only", facts["arms"]["published"]["status"])
            self.assertEqual("4.7.21003", facts["arms"]["published"]["mir_archive"]["version"])
            lua = self.lua()
            lua.globals().case_mods = _lua_value(lua, _mod_map(facts["profile"]["selection_without_mir"]))
            self.assertEqual(expected_profile, lua.execute("return bob_plates.select(case_mods)"))

    def test_material_stages_match_all_independent_published_missing_rows(self):
        for case in ("q097", "q098"):
            _, rows = self.technologies(case)
            expected = self.facts["cases"][case]["published_rows"]
            material_expected = {name: row for name, row in expected.items() if "_material_" in name}
            self.assertEqual(material_expected, rows, case)

    def test_base_ordinary_product_interface_matches_published_rows_without_emitting_them_here(self):
        lua = self.lua()
        facts = self.facts["cases"]["q097"]
        mods = _mod_map(facts["profile"]["selection_without_mir"])
        lua.globals().base_mods = _lua_value(lua, mods)
        products = _plain(lua.execute("return bob_plates.product_definitions(base_mods)"))
        self.assertEqual(
            {"research_carbon", "research_lithium", "research_tungsten"},
            {definition["key"] for definition in products},
        )
        values = _product_stream_values(definition["family"] for definition in products)
        lua.globals().product_values = _lua_value(lua, values)
        lua.globals().product_definitions = _lua_value(lua, products)
        rendered = _plain(lua.execute(r'''
          local out = {}
          for index, definition in ipairs(product_definitions) do
            local row = modern.technology(definition, product_values)
            out[row.name] = row
          end
          return out
        '''))
        expected = self.facts["cases"]["q097"]["published_rows"]
        self.assertEqual(
            {name: expected[name] for name in (
                "recipe-prod-research_carbon-1", "recipe-prod-research_lithium-1", "recipe-prod-research_tungsten-1"
            )},
            rendered,
        )
        self.assertEqual({}, _plain(lua.execute("return bob_plates.product_definitions({base='2.1.23'})")))

    def test_named_direct_route_drift_refuses_before_returning_rows(self):
        raw = self.raw_from_context("q097")
        raw["recipe"].pop("bob-aluminium-plate")
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().captured_values = _lua_value(lua, _stream_values(
            definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("base"))
        ))
        lua.globals().captured_mods = _lua_value(lua, _mod_map(self.facts["cases"]["q097"]["profile"]["selection_without_mir"]))
        ok, error = lua.execute(r'''
          return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("bob-aluminium-plate changed", error)

        changed = self.raw_from_context("q098")
        changed["recipe"]["bob-gold-plate"]["results"][0]["amount"] = 2
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, changed)
        lua.globals().captured_values = _lua_value(lua, _stream_values(
            definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("space-age"))
        ))
        lua.globals().captured_mods = _lua_value(lua, _mod_map(self.facts["cases"]["q098"]["profile"]["selection_without_mir"]))
        ok, error = lua.execute(r'''
          return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("bob-gold-plate changed", error)

        missing_owner = self.raw_from_context("q098")
        missing_owner["technology"].pop("bob-gold-processing")
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, missing_owner)
        lua.globals().captured_values = _lua_value(lua, _stream_values(
            definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("space-age"))
        ))
        lua.globals().captured_mods = _lua_value(lua, _mod_map(self.facts["cases"]["q098"]["profile"]["selection_without_mir"]))
        ok, error = lua.execute(r'''
          return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("bob-gold-processing no longer owns bob-gold-plate", error)

    def test_product_route_semantics_keep_native_defaults_but_refuse_unrepresented_drift(self):
        defaulted = self.raw_from_context("q097")
        defaulted["recipe"]["carbon"]["results"][0].update({
            # F210 only loads product ranges when fixed amount is absent.
            "amount_min": 0,
            "amount_max": 99,
            "probability": 1,
            "independent_probability": 1,
            "shared_probability": {"min": 0, "max": 1},
            "extra_count_fraction": 0,
            "catalyst_amount": 0,
            "ignored_by_productivity": 0,
            # F210 products inherit stats exclusion only when the explicit
            # productivity count is absent.  An explicit zero is equivalent
            # to the captured ordinary route even with independent stats.
            "ignored_by_stats": 7,
        })
        defaulted["recipe"]["carbon"]["ingredients"][0]["ignored_by_stats"] = 7
        _, rows = self.technologies("q097", raw=defaulted)
        self.assertIn("recipe-prod-research_material_bronze-1", rows)
        self.assertEqual(0, defaulted["recipe"]["carbon"]["results"][0]["ignored_by_productivity"])
        lithium = defaulted["recipe"]["bob-deuterium-fuel-reprocessing"]["results"]
        self.assertEqual((10, 10, .1), (
            lithium[0]["ignored_by_productivity"], lithium[0]["ignored_by_stats"],
            lithium[1]["independent_probability"],
        ))

        for key, value in (
            ("probability", .5), ("independent_probability", .5),
            ("shared_probability", {"min": 0, "max": .5}),
            ("extra_count_fraction", .5), ("catalyst_amount", 1),
            ("extra_count_fraction", False), ("ignored_by_productivity", 1),
            ("ignored_by_productivity", False), ("ignored_by_stats", 1),
        ):
            with self.subTest(product_field=key):
                changed = self.raw_from_context("q097")
                changed["recipe"]["carbon"]["results"][0][key] = value
                lua = self.lua()
                lua.globals().captured_raw = _lua_value(lua, changed)
                lua.globals().captured_values = _lua_value(lua, _stream_values(
                    definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("base"))
                ))
                lua.globals().captured_mods = _lua_value(
                    lua, _mod_map(self.facts["cases"]["q097"]["profile"]["selection_without_mir"])
                )
                ok, error = lua.execute(r'''
                  return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
                ''')
                self.assertFalse(ok)
                self.assertIn("carbon changed", error)

        changed = self.raw_from_context("q097")
        changed["recipe"]["carbon"]["ingredients"][0]["minimum_temperature"] = 1
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, changed)
        lua.globals().captured_values = _lua_value(lua, _stream_values(
            definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("base"))
        ))
        lua.globals().captured_mods = _lua_value(
            lua, _mod_map(self.facts["cases"]["q097"]["profile"]["selection_without_mir"])
        )
        ok, error = lua.execute(r'''
          return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("carbon changed", error)

        changed = self.raw_from_context("q097")
        self.assertEqual({"type": "fluid", "name": "water", "amount": 5}, changed["recipe"]["carbon"]["ingredients"][0])
        changed["recipe"]["carbon"]["ingredients"][0]["temperature"] = 100
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, changed)
        lua.globals().captured_values = _lua_value(lua, _stream_values(
            definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("base"))
        ))
        lua.globals().captured_mods = _lua_value(
            lua, _mod_map(self.facts["cases"]["q097"]["profile"]["selection_without_mir"])
        )
        ok, error = lua.execute(r'''
          return pcall(function() return bob_plates.technologies(captured_values, captured_raw, captured_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("carbon changed", error)

    def test_nondefault_tuning_is_rendered_after_preflight_and_definition_copies_are_fresh(self):
        lua = self.lua()
        first = _plain(lua.execute("return bob_plates_data.material_definitions('base')"))
        first[0]["routes"][0]["ingredients"][0]["amount"] = 999
        lua.globals().changed_definitions = _lua_value(lua, first)
        self.assertNotEqual(
            999,
            _plain(lua.execute("return bob_plates_data.material_definitions('base')"))[0]["routes"][0]["ingredients"][0]["amount"],
        )

        values = _stream_values(definition["key"] for definition in _plain(lua.globals().bob_plates_data.material_definitions("base")))
        values["streams"]["research_material_bronze"].update({
            "base_cost": 250, "linear_increment": 3, "growth_factor": 1.5, "research_time": 45, "effect_percent": 3,
        })
        _, rows = self.technologies("q097", values=values)
        early, continuation = rows["recipe-prod-research_material_bronze-1"], rows["recipe-prod-research_material_bronze-4"]
        self.assertEqual("(250+3*(L-1))*1.5^(L-1)", early["unit"]["count_formula"])
        self.assertEqual("874.125+250*(L-4)", continuation["unit"]["count_formula"])
        self.assertEqual(45, early["unit"]["time"])
        self.assertEqual([0.03], [effect["change"] for effect in continuation["effects"]])

    def test_inactive_or_conflicting_tuples_are_lazy_and_emit_no_rows(self):
        lua = self.lua()
        lua.globals().minimal_values = _lua_value(lua, {"streams": {}})
        lua.globals().empty_raw = _lua_value(lua, {})
        lua.globals().inactive_mods = _lua_value(lua, {"base": "2.1.23", "boblibrary": "3.0.1", "bobores": "3.0.0"})
        lua.globals().conflicted_mods = _lua_value(lua, {
            "base": "2.1.23", "boblibrary": "3.0.1", "bobores": "3.0.0", "bobplates": "3.0.2", "bobtech": "1.0.0"
        })
        self.assertEqual({}, _plain(lua.execute("return bob_plates.technologies(minimal_values, empty_raw, inactive_mods)")))
        self.assertEqual({}, _plain(lua.execute("return bob_plates.technologies(minimal_values, empty_raw, conflicted_mods)")))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobPlatesF210MaterialsTests)
    )
    raise SystemExit(not result.wasSuccessful())
