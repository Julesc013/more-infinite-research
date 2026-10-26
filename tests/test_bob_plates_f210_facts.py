"""Independent F210 Bob Plates material facts and reuse-boundary control.

The fixture projects only the completed EA41 q097/q098 upstream and published
prototype captures.  CE116's missing identities are retained as historical
scope, never as a source of expected technology fields.
"""

import argparse
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

RAW_SHA256 = {
    "q097": {
        "upstream": "ED44B652498FD1149A1DAA4992153D6CB5CAA73BDF19B897CB2630E91B7C4D67",
        "published": "E2276DE6B87B3C027350575827A6AC47DBE01560F9156D4914D177DCB5E5B2CB",
        "candidate": "310C21FD2DC311BE9C8D0635AB444D2CD9211E23815E78E103EE2232EB2FC740",
    },
    "q098": {
        "upstream": "D5874F94AFEFB5E56185AE33678739D93CA9F51D5D36A30CB91AD56C18BE8C6E",
        "published": "ABB7597863F2A5171AD91F1B8F73A742D32556BC7D668799D08CCC29B0662F81",
        "candidate": "B4F12FC54FF52E33E73AB187000972CE87CD9D419168C4AB837EF9FD26D081D4",
    },
}

CORE_FAMILIES = {
    "research_material_bronze",
    "research_material_copper_tungsten",
    "research_material_gunmetal",
    "research_material_invar",
    "research_material_lead",
    "research_material_nitinol",
    "research_material_tin",
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


def _science_names(row):
    names = []
    for ingredient in row["unit"]["ingredients"]:
        names.append(ingredient["name"] if isinstance(ingredient, dict) else ingredient[0])
    return names


def _effect_recipes(row):
    return [effect["recipe"] for effect in row["effects"]
            if effect.get("type") == "change-recipe-productivity"]


class BobPlatesF210FactsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if FACTS_PATH.stat().st_size > MAX_FACTS_BYTES:
            raise AssertionError("Bob Plates F210 facts exceed their 256 KiB compressed bound")
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        if cls.facts.get("schema") != "MIR5BobPlatesF210CapturedFactsV1":
            raise AssertionError("Bob Plates F210 facts schema changed")

        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.globals().source_root = SOURCE_ROOT.as_posix()
        cls.lua.execute(r'''
          package.path = source_root .. "/?.lua;" .. source_root .. "/?/init.lua"
          package.cpath = ""
          core_definitions = require("research.bob_core_materials")
          angel_definitions = require("research.bob_angel_materials")
          bobtech_definitions = require("research.bob_tech_materials")
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          core_profile = require("compatibility.bob_core_profile")
        ''')
        cls.core_definitions = {
            row["key"]: row for row in _plain(cls.lua.globals().core_definitions)
        }
        cls.angel_definitions = _plain(cls.lua.globals().angel_definitions)
        cls.bobtech_definitions = _plain(cls.lua.globals().bobtech_definitions)

    def _case(self, name):
        return self.facts["cases"][name]

    def test_exact_completed_capture_provenance_and_historical_scope_are_retained(self):
        self.assertLessEqual(FACTS_PATH.stat().st_size, MAX_FACTS_BYTES)
        scope = self.facts["scope"]
        self.assertEqual(F210_SHA256, scope["engine"]["sha256"])
        self.assertFalse(scope["claims"]["native_qualification"])
        self.assertFalse(scope["claims"]["release_qualification"])
        self.assertTrue(scope["claims"]["candidate_ce116_is_historical_only"])
        self.assertIn("candidate-derived expectations", self.facts["projection_rules"]["excludes"])

        for case in ("q097", "q098"):
            facts = self._case(case)
            self.assertEqual("MIR5PrototypeCaptureV1", facts["arms"]["upstream"]["kind"])
            self.assertEqual("completed-data-stage-observation-only", facts["arms"]["published"]["status"])
            self.assertFalse(facts["arms"]["published"]["native_qualification"])
            for arm in ("upstream", "published", "candidate"):
                self.assertEqual(RAW_SHA256[case][arm], facts["arms"][arm]["data_raw_sha256"])
            self.assertEqual("4.7.21003", facts["arms"]["published"]["mir_archive"]["version"])
            self.assertTrue(facts["published_rows"])
            self.assertNotIn("candidate_rows", facts)

    def test_exact_missing_identity_sets_are_complete_and_enabled_published_rows(self):
        q097 = self._case("q097")
        q098 = self._case("q098")
        self.assertEqual(31, len(q097["historical_candidate_missing_public_identities"]))
        self.assertEqual(16, len(q098["historical_candidate_missing_public_identities"]))
        self.assertEqual(set(q097["historical_candidate_missing_public_identities"]), set(q097["published_rows"]))
        self.assertEqual(set(q098["historical_candidate_missing_public_identities"]), set(q098["published_rows"]))
        self.assertIn("recipe-prod-research_carbon-1", q097["published_rows"])
        self.assertIn("recipe-prod-research_lithium-1", q097["published_rows"])
        self.assertIn("recipe-prod-research_tungsten-1", q097["published_rows"])
        self.assertNotIn("recipe-prod-research_carbon-1", q098["published_rows"])
        self.assertNotIn("recipe-prod-research_lithium-1", q098["published_rows"])
        for case in (q097, q098):
            for name, row in case["published_rows"].items():
                self.assertTrue(name.startswith("recipe-prod-research_"))
                self.assertNotEqual(False, row.get("enabled"), name)
                self.assertTrue(row["effects"], name)
                self.assertIsInstance(row["unit"]["time"], (int, float), name)
                self.assertTrue(row["unit"].get("count_formula"), name)

        disposition = self.facts["reuse_boundary"]["saved_identity_disposition"]
        self.assertEqual("no_disabled_saved_identity_witnessed", disposition["status"])

    def test_q098_seven_material_definitions_match_existing_bob_core_routes_and_stages(self):
        q098 = self._case("q098")
        selection = {entry["name"] for entry in q098["profile"]["selection_without_mir"]}
        self.assertNotIn("bobelectronics", selection)
        self.assertNotIn("bobtech", selection)
        self.lua.globals().q098_mods = _lua_value(
            self.lua, {entry["name"]: entry["version"] for entry in q098["profile"]["selection_without_mir"]}
        )
        self.assertFalse(self.lua.execute("return core_profile.applies(q098_mods)"))

        reuse = self.facts["reuse_boundary"]["q098_direct_definition_reuse"]
        self.assertEqual(CORE_FAMILIES, set(reuse["families"]))
        self.assertEqual(set(CORE_FAMILIES), set(self.core_definitions) & CORE_FAMILIES)
        for key in sorted(CORE_FAMILIES):
            definition = self.core_definitions[key]
            rows = reuse["published_rows"][key]
            early, continuation = rows["early"], rows["continuation"]
            route = definition["routes"][0]
            raw_route = q098["upstream_context"]["routes"][route["recipe"]]
            self.assertEqual(route["ingredients"], raw_route["recipe"]["ingredients"], key)
            self.assertEqual(route["results"], raw_route["recipe"]["results"], key)
            owners = raw_route["unlock_owners"]
            if route.get("owner") is None:
                self.assertEqual([], owners, key)
            else:
                self.assertEqual([route["owner"]], [owner["name"] for owner in owners], key)
            item = raw_route["recipe"]["results"][0]["name"]
            self.assertEqual(definition["item"], item, key)
            self.assertEqual(definition["icon"], q098["upstream_context"]["items"][item]["icon"], key)
            self.assertEqual(definition["icon_size"], q098["upstream_context"]["items"][item].get("icon_size", 64), key)

            for stage_name, row in (("early", early), ("continuation", continuation)):
                stage = definition[stage_name]
                self.assertEqual(stage["id"], row["name"], key + ":" + stage_name)
                self.assertEqual(stage["max_level"], row["max_level"], key + ":" + stage_name)
                self.assertEqual(stage["order"], row["order"], key + ":" + stage_name)
                self.assertEqual(stage["prerequisites"], row["prerequisites"], key + ":" + stage_name)
                self.assertEqual(stage["science"], _science_names(row), key + ":" + stage_name)
                self.assertEqual([route["recipe"]], _effect_recipes(row), key + ":" + stage_name)
                self.assertEqual([0.02], [effect["change"] for effect in row["effects"]], key + ":" + stage_name)
            self.assertFalse(continuation["show_levels_info"])
            self.assertTrue(continuation["visible_when_disabled"])

        self.assertEqual(
            {"recipe-prod-research_material_gold-1", "recipe-prod-research_material_gold-4"},
            set(self.facts["reuse_boundary"]["q098_additional_authored_family"]["rows"]),
        )

    def test_base_vectors_and_angel_routes_prove_the_reuse_boundary_is_not_a_whole_profile_admission(self):
        q097, q098 = self._case("q097"), self._case("q098")
        self.assertNotIn("space-age", {entry["name"] for entry in q097["profile"]["selection_without_mir"]})
        for key in CORE_FAMILIES:
            base_tail = q097["published_rows"][f"recipe-prod-{key}-4"]
            space_tail = q098["published_rows"][f"recipe-prod-{key}-4"]
            self.assertIn("utility-science-pack", _science_names(base_tail), key)
            self.assertIn("space-science-pack", _science_names(space_tail), key)
        self.assertEqual(
            ["bob-lead-plate", "bob-lead-plate-2"],
            _effect_recipes(q097["published_rows"]["recipe-prod-research_material_lead-1"]),
        )
        self.assertEqual(
            ["bob-lead-plate"],
            _effect_recipes(q098["published_rows"]["recipe-prod-research_material_lead-1"]),
        )
        q098_routes = set(q098["upstream_context"]["routes"])
        bobtech_routes = {
            route["recipe"] for definition in self.bobtech_definitions for route in definition["routes"]
        }
        self.assertTrue(bobtech_routes)
        self.assertTrue(all(name.startswith("angels-") for name in bobtech_routes))
        self.assertFalse(q098_routes & bobtech_routes)

        angel_routes = {
            route["recipe"] for definition in self.angel_definitions for route in definition["routes"]
        }
        # The same copper-tungsten recipe identity exists in both selections,
        # but Angel's route is not interchangeable: its ingredients and owner
        # are different captured native facts.
        self.assertEqual({"bob-copper-tungsten-alloy"}, q098_routes & angel_routes)
        angel_route = next(
            route for definition in self.angel_definitions for route in definition["routes"]
            if route["recipe"] == "bob-copper-tungsten-alloy"
        )
        q098_route = q098["upstream_context"]["routes"]["bob-copper-tungsten-alloy"]
        self.assertNotEqual(angel_route["ingredients"], q098_route["recipe"]["ingredients"])
        self.assertNotEqual(angel_route["owner"], q098_route["unlock_owners"][0]["name"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobPlatesF210FactsTests)
    )
    raise SystemExit(not result.wasSuccessful())
