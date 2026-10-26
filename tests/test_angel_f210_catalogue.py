"""Independent q007/q008 facts for the detached F210 pure-Angel adapter.

This is data/profile/preflight coverage only. Central selection, settings and
publication remain root-owned and require their own full-pipeline controls.
"""

import argparse
import copy
import gzip
import hashlib
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source"
FACTS_PATH = ROOT / "tests/fixtures/angel-f210-captured-facts.json.gz"


def _plain(value):
    if not hasattr(value, "items"):
        return value
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(nested) for key, nested in values.items()}


def _lua_value(lua, value):
    if isinstance(value, list):
        return lua.table_from([_lua_value(lua, nested) for nested in value])
    if isinstance(value, dict):
        return lua.table_from({key: _lua_value(lua, nested) for key, nested in value.items()})
    return value


def _effects(technology):
    return [(row["recipe"], row["change"]) for row in technology["effects"]]


def _definition_effects(definition, effect_percent=10):
    return [(row["recipe"], effect_percent * row["scale"] / 100) for row in definition["effects"]]


class AngelF210CatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            from lupa.lua52 import LuaRuntime
        except ImportError as error:
            raise AssertionError("MIR pinned Lua runtime is required for Angel F210 controls") from error
        cls.facts_bytes = gzip.decompress(FACTS_PATH.read_bytes())
        cls.facts = json.loads(cls.facts_bytes)
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        source = str(SOURCE_ROOT).replace("\\", "/")
        cls.lua.execute(f"package.path = '{source}/?.lua;{source}/?/init.lua;' .. package.path")
        adapter = cls.lua.eval("require('compatibility.modern_catalogue.angel_f210')")
        profile = cls.lua.eval("require('compatibility.angel_f210_profile')")
        if isinstance(adapter, tuple):
            adapter = adapter[0]
        if isinstance(profile, tuple):
            profile = profile[0]
        cls.adapter = _plain(adapter)
        cls.profile = _plain(profile)
        cls._preflight = cls.lua.eval(
            "function(raw, profile) return pcall(function() return require('compatibility.modern_catalogue.angel_f210').preflight(raw, profile) end) end"
        )
        cls._select = cls.lua.eval("function(active) return require('compatibility.angel_f210_profile').select(active) end")

    def _active(self, capture):
        return {row["name"]: row["version"] for row in self.facts["captures"][capture]["upstream"]["selected_archives"]}

    def _published(self, capture, identifier):
        return self.facts["captures"][capture]["published"]["technologies"][identifier]

    def _science(self, name):
        return self.adapter["science"][name]

    def _assert_effects(self, expected, actual, percent=10):
        self.assertEqual(_effects(expected), _definition_effects(actual, percent))

    def test_fixture_is_upstream_and_published_only_with_exact_r04_provenance(self):
        self.assertEqual(self.facts["schema"], "MIR5AngelF210CapturedFactsV1")
        self.assertIn("no candidate raw/settings/result", self.facts["scope"])
        self.assertEqual(self.facts["r04"]["plan_sha256"], "524425A246135ECAA957A472D1E70B87D96F21CD2164887E78D8CC0ED9693E85")
        self.assertEqual(self.facts["r04"]["source_head"], "13283e85115ac460380b872a20242dffa71d5d6c")
        self.assertEqual(self.facts["r04"]["engine_sha256"], "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060")
        self.assertEqual(self.facts["r04"]["published_mir_archive_sha256"], "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852")
        for capture in self.facts["captures"].values():
            self.assertRegex(capture["upstream"]["raw_sha256"], r"^[A-F0-9]{64}$")
            self.assertRegex(capture["published"]["raw_sha256"], r"^[A-F0-9]{64}$")
            self.assertEqual(capture["published"]["mir_archive_sha256"], self.facts["r04"]["published_mir_archive_sha256"])
        self.assertEqual(
            self.facts["q009_exclusion_fact"]["changed_route_fields"],
            {"angels-plate-aluminium": ["results"], "angels-plate-aluminium-2": ["results"]},
        )

    def test_profile_selects_only_pure_angel_base_and_space_age(self):
        base = self._active("base")
        space_age = self._active("space_age")
        self.assertEqual(self._select(_lua_value(self.lua, base)), "base")
        self.assertEqual(self._select(_lua_value(self.lua, space_age)), "space-age")
        rejected = dict(base, bobplates="3.0.2")
        self.assertIsNone(self._select(_lua_value(self.lua, rejected)))
        missing = dict(base)
        del missing["angelssmelting"]
        self.assertIsNone(self._select(_lua_value(self.lua, missing)))

    def test_base_literal_breeding_effects_and_research_speed_match_b6(self):
        breeding = self._published("base", "recipe-prod-research_breeding-1")
        addition = self.adapter["base"]["additions"][0]
        self.assertEqual(addition["key"], "research_breeding")
        self.assertEqual(self._science(addition["science"]), [name for name, _ in breeding["unit"]["ingredients"]])
        self.assertEqual(addition["prerequisites"], breeding["prerequisites"])
        self._assert_effects(breeding, addition)
        self.assertEqual(addition["icon"], breeding["icons"][0]["icon"])
        self.assertEqual(addition["icon_size"], breeding["icons"][0]["icon_size"])
        self.assertEqual(addition["tuning"], {
            "base_cost": 8000, "effect_percent": 10, "enabled": True, "growth_factor": 2,
            "linear_increment": 0, "max_level": 0, "research_time": 60,
        })

        continuation = self.adapter["base"]["continuation_overrides"]["research_speed"]
        expected = self._published("base", "research-speed-7")
        self.assertEqual(self._science(continuation["science"]), [name for name, _ in expected["unit"]["ingredients"]])
        self.assertEqual(continuation["prerequisites"], expected["prerequisites"])

    def test_base_literal_named_effect_replacements_and_aluminium_stages_match_b6(self):
        overrides = self.adapter["base"]["definition_overrides"]
        expected_ids = {
            "research_lubricant_productivity": "recipe-prod-research_lubricant_productivity-1",
            "research_steel": "recipe-prod-research_steel-1",
            "research_sulfur": "recipe-prod-research_sulfur-1",
            "research_sulfuric_acid_productivity": "recipe-prod-research_sulfuric_acid_productivity-1",
        }
        self.assertEqual(set(overrides), set(expected_ids))
        for family, identifier in expected_ids.items():
            self._assert_effects(self._published("base", identifier), overrides[family])
        self.assertEqual(overrides["research_sulfur"]["icons"], self._published("base", "recipe-prod-research_sulfur-1")["icons"])
        self.assertEqual(
            overrides["research_sulfuric_acid_productivity"]["icons"],
            self._published("base", "recipe-prod-research_sulfuric_acid_productivity-1")["icons"],
        )

        stages = self.adapter["base"]["material_stages"]
        self.assertEqual(len(stages), 1)
        stage = stages[0]
        early = self._published("base", "recipe-prod-research_material_aluminium-1")
        tail = self._published("base", "recipe-prod-research_material_aluminium-4")
        self.assertEqual(stage["key"], "research_material_aluminium")
        self.assertEqual(stage["item"], "angels-plate-aluminium")
        self.assertEqual(stage["icon"], early["icons"][0]["icon"])
        self.assertEqual(stage["icon_size"], early["icons"][0]["icon_size"])
        self.assertEqual(_effects(early), _definition_effects({"effects": stage["effects"]}, 2))
        self.assertEqual(self._science(stage["early"]["science"]), [name for name, _ in early["unit"]["ingredients"]])
        self.assertEqual(stage["early"]["prerequisites"], early["prerequisites"])
        self.assertEqual(stage["early"]["max_level"], early["max_level"])
        self.assertEqual(stage["early"]["order"], early["order"])
        self.assertEqual(self._science(stage["continuation"]["science"]), [name for name, _ in tail["unit"]["ingredients"]])
        self.assertEqual(stage["continuation"]["prerequisites"], tail["prerequisites"])
        self.assertEqual(stage["continuation"]["max_level"], tail["max_level"])
        self.assertEqual(stage["continuation"]["order"], tail["order"])

    def test_space_age_exact_effect_science_and_native_steel_delta_match_b6(self):
        overrides = self.adapter["space_age"]["definition_overrides"]
        expected_ids = {
            "research_breeding": "recipe-prod-research_breeding-1",
            "research_lubricant_productivity": "recipe-prod-research_lubricant_productivity-1",
            "research_oil_processing_productivity": "recipe-prod-research_oil_processing_productivity-1",
            "research_science_pack_productivity": "recipe-prod-research_science_pack_productivity-1",
            "research_sulfur": "recipe-prod-research_sulfur-1",
            "research_sulfuric_acid_productivity": "recipe-prod-research_sulfuric_acid_productivity-1",
        }
        self.assertEqual(set(overrides), set(expected_ids))
        for family, identifier in expected_ids.items():
            self._assert_effects(self._published("space_age", identifier), overrides[family])
        science = overrides["research_science_pack_productivity"]
        expected_science = self._published("space_age", "recipe-prod-research_science_pack_productivity-1")
        self.assertEqual(self._science(science["science"]), [name for name, _ in expected_science["unit"]["ingredients"]])
        self.assertEqual(science["prerequisites"], expected_science["prerequisites"])
        self.assertEqual(overrides["research_sulfur"]["icons"], self._published("space_age", "recipe-prod-research_sulfur-1")["icons"])
        self.assertEqual(overrides["research_sulfuric_acid_productivity"]["icons"], self._published("space_age", "recipe-prod-research_sulfuric_acid_productivity-1")["icons"])

        continuation = self.adapter["space_age"]["continuation_overrides"]["research_speed"]
        expected_speed = self._published("space_age", "research-speed-7")
        self.assertEqual(self._science(continuation["science"]), [name for name, _ in expected_speed["unit"]["ingredients"]])
        self.assertEqual(continuation["prerequisites"], expected_speed["prerequisites"])
        native = self.adapter["space_age"]["native_owners"]["research_steel"]
        steel = self._published("space_age", "steel-plate-productivity")
        self.assertEqual(native["id"], "steel-plate-productivity")
        self.assertEqual(native["expected"]["prerequisites"], steel["prerequisites"])
        self.assertEqual(native["expected"]["ingredients"], steel["unit"]["ingredients"])
        self.assertEqual(native["expected"]["count_formula"], steel["unit"]["count_formula"])
        self.assertEqual(native["expected"]["research_time"], steel["unit"]["time"])
        self.assertEqual(native["expected"]["recipes"], [row["recipe"] for row in steel["effects"]])

    def test_preflight_uses_only_named_facts_and_never_mutates_raw(self):
        for capture, profile in (("base", "base"), ("space_age", "space-age")):
            upstream = self.facts["captures"][capture]["upstream"]
            raw = {"recipe": copy.deepcopy(upstream["recipes"]), "technology": copy.deepcopy(upstream["technologies"])}
            before = json.dumps(raw, sort_keys=True)
            ok, value = self._preflight(_lua_value(self.lua, raw), profile)
            self.assertTrue(ok, (capture, value))
            self.assertEqual(_plain(value), self.adapter[profile.replace("-", "_")])
            self.assertEqual(json.dumps(raw, sort_keys=True), before)

        base = self.facts["captures"]["base"]["upstream"]
        missing = {"recipe": copy.deepcopy(base["recipes"]), "technology": copy.deepcopy(base["technologies"])}
        del missing["recipe"]["angels-plate-aluminium"]
        ok, message = self._preflight(_lua_value(self.lua, missing), "base")
        self.assertFalse(ok)
        self.assertIn("angels-plate-aluminium changed", str(message))
        invalid_owner = {"recipe": copy.deepcopy(base["recipes"]), "technology": copy.deepcopy(base["technologies"])}
        invalid_owner["technology"]["angels-aluminium-casting-2"]["unit"]["ingredients"][2][1] = "wrong-pack"
        ok, message = self._preflight(_lua_value(self.lua, invalid_owner), "base")
        self.assertFalse(ok)
        self.assertIn("angels-aluminium-casting-2 science changed", str(message))
        wrong_output = {"recipe": copy.deepcopy(base["recipes"]), "technology": copy.deepcopy(base["technologies"])}
        wrong_output["recipe"]["angels-plate-aluminium"]["results"][0]["amount"] = 5
        ok, message = self._preflight(_lua_value(self.lua, wrong_output), "base")
        self.assertFalse(ok)
        self.assertIn("angels-plate-aluminium changed", str(message))
        space = self.facts["captures"]["space_age"]["upstream"]
        wrong_native = {"recipe": copy.deepcopy(space["recipes"]), "technology": copy.deepcopy(space["technologies"])}
        wrong_native["technology"]["steel-plate-productivity"]["unit"]["count_formula"] = "wrong"
        ok, message = self._preflight(_lua_value(self.lua, wrong_native), "space-age")
        self.assertFalse(ok)
        self.assertIn("steel-plate-productivity changed", str(message))

    def test_adapter_is_literal_data_and_has_no_policy_world_access(self):
        source = (SOURCE_ROOT / "compatibility/modern_catalogue/angel_f210.lua").read_text(encoding="utf-8")
        self.assertNotIn("data.raw", source)
        self.assertNotIn("active_mods", source)
        self.assertNotIn("pairs(raw", source)
        self.assertNotIn("next(raw", source)
        self.assertEqual(hashlib.sha256(gzip.decompress(FACTS_PATH.read_bytes())).hexdigest().upper(), hashlib.sha256(self.facts_bytes).hexdigest().upper())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AngelF210CatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
