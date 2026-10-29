"""Captured F210 Py HighTech data delta; no native result is claimed."""

import argparse
import gzip
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/py-f210-captured-facts.json.gz"
SOURCE_ROOT = ROOT / "source"


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(nested) for key, nested in items.items()}


def _require_lua(module):
    try:
        from lupa.lua52 import LuaRuntime
    except ImportError as error:
        raise AssertionError("MIR pinned Lua runtime is required for F210 Py controls") from error
    lua = LuaRuntime(unpack_returned_tuples=True)
    root = str(SOURCE_ROOT).replace("\\", "/")
    lua.execute(f"package.path = '{root}/?.lua;{root}/?/init.lua;' .. package.path")
    result = lua.eval(f"require('{module}')")
    if isinstance(result, tuple):
        result = result[0]
    return _plain(result)


def _effects(technology):
    return [(effect["recipe"], effect["change"]) for effect in technology["effects"]]


class PyF210CatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with gzip.open(FACTS_PATH, "rt", encoding="utf-8") as stream:
            cls.facts = json.load(stream)
        cls.delta = _require_lua("compatibility.modern_catalogue.py_f210")
        cls.f200 = _require_lua("compatibility.modern_catalogue.py")

    @property
    def q001(self):
        return self.facts["captures"]["q001_py_hightech_base"]

    @property
    def q003(self):
        return self.facts["captures"]["q003_py_hightech_productivity_base"]

    def test_frozen_capture_scope_and_complete_relevant_published_rows(self):
        self.assertEqual(self.facts["schema"], "MIR5PyF210CapturedFactsV1")
        self.assertEqual(self.facts["engine"], {
            "target": "f210",
            "factorio_version": "2.1",
            "base_version": "2.1.23",
            "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
        })
        for capture, productivity in ((self.q001, False), (self.q003, True)):
            self.assertEqual(len(capture["published_rows"]), 49)
            self.assertEqual(capture["arms"]["published"]["status"], "completed-data-stage-observation-only")
            self.assertEqual(capture["arms"]["published"]["mir_archive"], {
                "name": "more-infinite-research",
                "version": "4.7.21003",
                "factorio_version": "2.1",
                "sha256": "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852",
            })
            for arm in ("upstream", "published"):
                self.assertRegex(capture["data_raw"][arm]["sha256"], r"^[A-F0-9]{64}$")
                self.assertGreater(capture["data_raw"][arm]["bytes"], 60_000_000)
            selected = {row["name"]: row["version"] for row in capture["profile"]["selected_mods"]}
            self.assertEqual(selected["base"], "2.1.23")
            self.assertEqual(selected["pycoalprocessing"], "3.1.8")
            self.assertEqual(selected["pyalienlife"], "3.1.8")
            self.assertEqual(selected["pyhightech"], "3.1.5")
            self.assertEqual("py_productivity" in selected, productivity)

    def test_literal_module_is_data_only_and_contains_no_capture_provenance(self):
        source = (SOURCE_ROOT / "compatibility/modern_catalogue/py_f210.lua").read_text(encoding="utf-8")
        for forbidden in ("function", "require(", "data.raw", "active_mods", "sha256", "pairs(", "ipairs("):
            self.assertNotIn(forbidden, source)
        self.assertEqual(set(self.delta), {
            "continuation_native_facts",
            "breeding_required_target_additions",
            "exact_product_targets",
            "retained_disabled_identities",
            "additions",
            "py_productivity",
        })

    def test_f210_continuation_native_facts_and_research_speed_presentation(self):
        expected_ids = self.facts["continuation_ids"]
        self.assertEqual(set(self.delta["continuation_native_facts"]), set(expected_ids))
        for key, technology_id in expected_ids.items():
            delta = self.delta["continuation_native_facts"][key]
            native = self.q001["upstream_continuations"][key]
            published = self.q001["published_continuations"][key]
            self.assertEqual(delta["id"], technology_id)
            self.assertEqual(delta["previous"]["name"], native["previous"]["name"])
            self.assertEqual(delta["previous"]["count"], native["previous"]["unit"]["count"])
            self.assertEqual(delta["predecessor"]["name"], native["predecessor"]["name"])
            self.assertEqual(delta["predecessor"]["count"], native["predecessor"]["unit"]["count"])
            self.assertEqual(delta["predecessor"]["time"], native["predecessor"]["unit"]["time"])
            self.assertEqual(delta["predecessor"]["ingredients"], native["predecessor"]["unit"]["ingredients"])
            self.assertEqual(delta["predecessor"]["prerequisites"], native["predecessor"]["prerequisites"])
            self.assertEqual(delta["predecessor"]["effects"], native["predecessor"]["effects"])
            self.assertEqual(delta["inheritance"], {
                "last_count": native["predecessor"]["unit"]["count"],
                "previous_count": native["previous"]["unit"]["count"],
                "research_time": native["predecessor"]["unit"]["time"],
            })
            self.assertEqual(delta["order"], published["order"])
        presentation = self.delta["continuation_native_facts"]["research_speed"]["presentation"]
        published = self.q001["published_continuations"]["research_speed"]
        self.assertEqual(presentation["icon_size"], published["icon_size"])
        self.assertEqual(presentation["icons"], published["icons"])
        self.assertEqual(len(presentation["icons"]), 3)
        self.assertEqual(presentation["icons"][1]["scale"], 0.7)

    def test_breeding_lithium_and_disabled_battery_are_exact_and_separate(self):
        f200_targets = _plain(self.f200["required_targets"]())["research_breeding"]
        self.assertEqual(len(f200_targets), 33)
        q001_breeding = self.q001["published_rows"]["recipe-prod-research_breeding-1"]
        published_targets = [effect["recipe"] for effect in q001_breeding["effects"]]
        xeno_position = f200_targets.index("yaedols-culture-mk01")
        self.assertEqual(published_targets, f200_targets[:xeno_position] + ["xeno-rc-breeding"] + f200_targets[xeno_position:])
        self.assertEqual(self.delta["breeding_required_target_additions"], ["xeno-rc-breeding"])
        self.assertNotIn("recipe-prod-research_batteries-1", self.q001["published_rows"])
        self.assertNotIn("recipe-prod-research_batteries-1", self.q003["published_rows"])
        disabled = self.delta["retained_disabled_identities"]
        self.assertEqual(set(disabled), {"research_batteries"})
        self.assertIs(disabled["research_batteries"]["available"], False)
        self.assertFalse(disabled["research_batteries"]["effects"])
        self.assertIn("research_batteries", self.f200["hightech_replacement_families"])

        addition = self.delta["additions"]
        self.assertEqual(len(addition), 1)
        lithium = addition[0]
        published = self.q001["published_rows"]["recipe-prod-research_lithium-1"]
        self.assertEqual(lithium["key"], "research_lithium")
        self.assertEqual(lithium["family"], "research_lithium")
        self.assertEqual(lithium["effects"], [{"recipe": "lithium", "scale": 0.5}])
        self.assertEqual(_effects(published), [("lithium", 0.05)])
        self.assertEqual(lithium["icon"], published["icons"][0]["icon"])
        self.assertEqual(lithium["icon_size"], published["icons"][0]["icon_size"])
        self.assertEqual(lithium["order"], published["order"])
        self.assertEqual(published["unit"]["ingredients"], [
            ["automation-science-pack", 1], ["logistic-science-pack", 1],
            ["chemical-science-pack", 1], ["production-science-pack", 1],
        ])

    def test_default_product_routes_are_exact_not_a_blanket_productivity_rule(self):
        expected = {
            "research_plastic": [
                "aromatics-to-plastic", "nylon-plastic", "plastic-bar-02", "plastic2", "plastic3", "plastics-mk03",
            ],
            "research_steel": ["steel-plate"],
        }
        self.assertEqual(self.delta["exact_product_targets"], expected)
        for family, recipes in expected.items():
            published = self.q001["published_rows"][f"recipe-prod-{family}-1"]
            self.assertEqual(_effects(published), [(recipe, 0.1) for recipe in recipes], family)
            self.assertEqual(_effects(self.q003["published_rows"][f"recipe-prod-{family}-1"]),
                             [(recipe, 0.1) for recipe in recipes], family)

    def test_productivity_addon_is_separately_selected_with_per_family_vectors(self):
        addon = self.delta["py_productivity"]
        self.assertEqual(addon["mod"], "py_productivity")
        expected = {
            "research_copper": ["copper-plate", "copper-plate-1", "copper-plate-4", "low-grade-smelting-copper"],
            "research_copper_cable": ["copper-cable"],
            "research_engine": ["engine-unit", "engine-unit-2"],
            "research_gears": ["iron-gear-wheel"],
            "research_iron": ["iron-oxide-smelting", "iron-plate", "iron-plate-1", "low-grade-smelting-iron"],
            "research_iron_sticks": ["cage-recycle-into-titanium", "iron-stick"],
            "research_plastic": ["aromatics-to-plastic", "nylon-plastic", "plastic-bar-02", "plastic2", "plastic3", "plastics-mk03"],
            "research_steel": ["steel-plate"],
            "research_sulfur": [
                "bitumen-to-sulfur", "cadaveric-to-sulfur", "calcinate-separation", "extract-ammonia-scrude",
                "extract-nitrogen-scrude", "extract-olefin-scrude", "extract-sulfur", "fawogae-to-sulfur",
                "molybdenum-oxide", "oleo-heavy", "outlet-gas-02", "outlet-gas-03", "yaedol-to-sulfur",
            ],
        }
        self.assertEqual(addon["exact_product_targets"], expected)
        q001_mods = {row["name"] for row in self.q001["profile"]["selected_mods"]}
        q003_mods = {row["name"] for row in self.q003["profile"]["selected_mods"]}
        self.assertNotIn(addon["mod"], q001_mods)
        self.assertIn(addon["mod"], q003_mods)
        for family, recipes in expected.items():
            published = self.q003["published_rows"][f"recipe-prod-{family}-1"]
            self.assertEqual(_effects(published), [(recipe, 0.1) for recipe in recipes], family)
        changed = {
            name for name in self.q001["published_rows"]
            if self.q001["published_rows"][name] != self.q003["published_rows"][name]
        }
        self.assertEqual(changed, {
            "recipe-prod-research_copper-1", "recipe-prod-research_copper_cable-1",
            "recipe-prod-research_engine-1", "recipe-prod-research_gears-1", "recipe-prod-research_iron-1",
            "recipe-prod-research_iron_sticks-1", "recipe-prod-research_sulfur-1",
        })
        self.assertIn("hotair-casting-engine-unit", [recipe for recipe, _ in _effects(
            self.q001["published_rows"]["recipe-prod-research_engine-1"]
        )])
        self.assertNotIn("hotair-casting-engine-unit", [recipe for recipe, _ in _effects(
            self.q003["published_rows"]["recipe-prod-research_engine-1"]
        )])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PyF210CatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
