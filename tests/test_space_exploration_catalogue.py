"""Literal F210 Space Exploration/K2SE catalogue deltas; no native result claimed."""

import json
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/space-exploration-f210-captured-facts.json"
SOURCE_ROOT = ROOT / "source"
sys.path.insert(0, str(ROOT / "tools"))


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
    except ImportError as error:  # Pinned runtime is required by the host plan.
        raise AssertionError("MIR pinned Lua runtime is required for SE catalogue controls") from error
    lua = LuaRuntime(unpack_returned_tuples=True)
    root = str(SOURCE_ROOT).replace("\\", "/")
    lua.execute(f"package.path = '{root}/?.lua;{root}/?/init.lua;' .. package.path")
    # These literal data modules must remain independently loadable: selection,
    # data.raw inspection, and central emission belong to the root-owned caller.
    result = lua.eval(f"require('{module}')")
    if isinstance(result, tuple):
        result = result[0]
    return _plain(result)


def _science_names(technology):
    ingredients = technology["unit"]["ingredients"]
    if any(amount != 1 for _, amount in ingredients):
        raise AssertionError("captured SE science packs must retain unit amount one")
    return [name for name, _ in ingredients]


def _productivity_effects(technology, effect_percent=10):
    result = []
    for effect in technology["effects"]:
        if effect["type"] != "change-recipe-productivity":
            raise AssertionError(f"unexpected direct effect in productivity technology: {effect}")
        result.append((effect["recipe"], effect["change"] * 100 / effect_percent))
    return result


def _module_effects(definition):
    return [(effect["recipe"], effect["scale"]) for effect in definition["effects"]]


CONTINUATION_IDS = {
    "braking_force": "braking-force-8",
    "inserter_capacity_bonus": "inserter-capacity-bonus-8",
    "laser_shooting_speed": "laser-shooting-speed-8",
    "research_speed": "research-speed-7",
    "weapon_shooting_speed": "weapon-shooting-speed-7",
    "worker_robots_storage": "worker-robots-storage-4",
}

# modern.lua interprets ordinary scales as effect-percent fractions and the
# three capacity/storage types as absolute values.  These captured values are
# deliberately nonuniform, so this protects the authored overlay from merely
# preserving effect names while changing its scalar behaviour.
CONTINUATION_PERCENT = {
    "braking_force": 15,
    "inserter_capacity_bonus": 4,
    "laser_shooting_speed": 50,
    "research_speed": 60,
    "weapon_shooting_speed": 40,
    "worker_robots_storage": 1,
}
ABSOLUTE_CONTINUATION_TYPES = {
    "inserter-stack-size-bonus",
    "bulk-inserter-capacity-bonus",
    "worker-robot-storage",
}

# Published native setting defaults are family-specific. Mining-drill
# productivity is 20%; character mining speed is 5%, rather than the common 10%.
DEFINITION_EFFECT_PERCENT = {"research_mining_drill": 20, "research_character_mining_speed": 5}


class SpaceExplorationCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        cls.se = _require_lua("compatibility.modern_catalogue.space_exploration")
        cls.k2se = _require_lua("compatibility.modern_catalogue.k2_space_exploration")

    def assertEffectsAlmostEqual(self, expected, actual):
        self.assertEqual([name for name, _ in actual], [name for name, _ in expected])
        self.assertEqual(len(actual), len(expected))
        for (_, actual_scale), (_, expected_scale) in zip(actual, expected):
            self.assertAlmostEqual(actual_scale, expected_scale, places=12)

    def _assert_delta_definitions(self, capture_name, delta, changed_names):
        technologies = self.facts["captures"][capture_name]["technologies"]
        expected_definition_keys = {
            name.removeprefix("recipe-prod-").removesuffix("-1")
            for name in changed_names
            if name.startswith("recipe-prod-") and name not in self.facts["se_addition_names"]
            and name != "recipe-prod-research_gears-1"
        }
        self.assertEqual(set(delta["definition_overrides"]), expected_definition_keys)
        for key in sorted(expected_definition_keys):
            technology = technologies[f"recipe-prod-{key}-1"]
            definition = delta["definition_overrides"][key]
            if "science" in definition:
                self.assertEqual(delta["science"][definition["science"]], _science_names(technology), key)
            if "prerequisites" in definition:
                self.assertEqual(definition["prerequisites"], technology["prerequisites"], key)
            if "icons" in definition:
                self.assertEqual(definition["icons"], technology["icons"], key)
            if capture_name == "k2se":
                inherited = self.facts["captures"]["se"]["technologies"][f"recipe-prod-{key}-1"]
                for field in ("science", "prerequisites", "effects", "icons"):
                    if field not in definition:
                        captured_field = "unit" if field == "science" else field
                        self.assertEqual(inherited[captured_field], technology[captured_field], (key, field))
            if "effects" not in definition:
                continue
            direct = [row for row in technology["effects"] if row["type"] != "change-recipe-productivity"]
            if direct:
                self.assertEqual(
                    [(row["type"], row.get("ammo_category")) for row in definition["effects"]],
                    [(row["type"], row.get("ammo_category")) for row in direct],
                    key,
                )
                self.assertTrue(all(row.get("raw") is False for row in definition["effects"]), key)
                for authored, captured in zip(definition["effects"], direct):
                    self.assertAlmostEqual(
                        captured["modifier"],
                        DEFINITION_EFFECT_PERCENT.get(key, 10) * authored["scale"] / 100,
                        places=12,
                        msg=key,
                    )
            else:
                self.assertEffectsAlmostEqual(
                    _productivity_effects(technology, DEFINITION_EFFECT_PERCENT.get(key, 10)),
                    _module_effects(definition),
                )

    def _assert_continuations(self, capture_name, delta, expected_keys):
        technologies = self.facts["captures"][capture_name]["technologies"]
        self.assertEqual(set(delta["continuation_overrides"]), expected_keys)
        for key in sorted(expected_keys):
            technology = technologies[CONTINUATION_IDS[key]]
            definition = dict(delta["continuation_overrides"][key])
            if capture_name == "k2se":
                definition = {**self.se["continuation_overrides"][key], **definition}
            science = delta["science"].get(definition["science"], self.se["science"].get(definition["science"]))
            self.assertEqual(science, _science_names(technology), key)
            self.assertEqual(definition["prerequisites"], technology["prerequisites"], key)
            expected_effects = technology["effects"]
            actual_effects = definition["effects"]
            self.assertEqual(
                [(row["type"], row.get("ammo_category")) for row in actual_effects],
                [(row["type"], row.get("ammo_category")) for row in expected_effects],
                key,
            )
            percent = CONTINUATION_PERCENT[key]
            for authored, captured in zip(actual_effects, expected_effects):
                expected_modifier = percent * authored["scale"]
                if authored["type"] not in ABSOLUTE_CONTINUATION_TYPES:
                    expected_modifier /= 100
                self.assertAlmostEqual(captured["modifier"], expected_modifier, places=12, msg=key)
            unit = technology["unit"]
            self.assertEqual(technology["max_level"], "infinite", key)
            self.assertIsInstance(unit["count_formula"], str, key)
            self.assertGreater(unit["time"], 0, key)

    def test_captured_full_catalogues_and_literal_delta_domains(self):
        se_rows = self.facts["captures"]["se"]["technologies"]
        k2se_rows = self.facts["captures"]["k2se"]["technologies"]
        self.assertEqual(len(se_rows), 55)
        self.assertEqual(len(k2se_rows), 55)
        self.assertEqual(len(self.facts["se_candidate_difference_names"]), 31)
        self.assertEqual(len(self.facts["k2se_overlay_difference_names"]), 20)
        self.assertEqual(
            set(se_rows) - set(self.facts["k2se_overlay_difference_names"]),
            {name for name in se_rows if se_rows[name] == k2se_rows[name]},
        )
        self.assertTrue(set(self.facts["k2se_overlay_difference_names"]).issubset(se_rows))
        for capture in self.facts["captures"].values():
            self.assertRegex(capture["source_data_raw_dump_sha256"], r"^[A-F0-9]{64}$")

    def test_se_literal_science_productivity_continuation_and_breeding_delta(self):
        self._assert_delta_definitions("se", self.se, self.facts["se_candidate_difference_names"])
        self._assert_continuations("se", self.se, set(CONTINUATION_IDS))
        self.assertEqual(len(self.se["additions"]), 1)
        addition = self.se["additions"][0]
        breeding = self.facts["captures"]["se"]["technologies"]["recipe-prod-research_breeding-1"]
        self.assertEqual(addition["key"], "research_breeding")
        self.assertEqual(self.se["science"][addition["science"]], _science_names(breeding))
        self.assertEqual(addition["prerequisites"], breeding["prerequisites"])
        self.assertEqual(addition["icons"], breeding["icons"])
        self.assertEffectsAlmostEqual(_productivity_effects(breeding), _module_effects(addition))
        self.assertEqual(addition["tuning"], {
            "base_cost": 8000,
            "effect_percent": 10,
            "enabled": True,
            "growth_factor": 2,
            "linear_increment": 0,
            "max_level": 0,
            "research_time": 60,
        })

    def test_k2se_extends_only_captured_overlay_rows(self):
        self._assert_delta_definitions("k2se", self.k2se, self.facts["k2se_overlay_difference_names"])
        self._assert_continuations(
            "k2se",
            self.k2se,
            {"inserter_capacity_bonus", "laser_shooting_speed", "research_speed", "weapon_shooting_speed", "worker_robots_storage"},
        )
        self.assertFalse(self.k2se["additions"])
        self.assertNotIn("braking_force", self.k2se["continuation_overrides"])
        self.assertEqual(
            self.k2se["science"]["science_se_k2_research_speed"],
            _science_names(self.facts["captures"]["k2se"]["technologies"]["research-speed-7"]),
        )

    def test_exact_product_bindings_cover_captured_productivity_effects_without_discovery(self):
        for capture_name, delta in (("se", self.se), ("k2se", self.k2se)):
            bindings = {}
            for binding in delta["exact_product_bindings"]:
                self.assertTrue(binding["include_recycling"])
                self.assertTrue(binding["allow_shared_input_output"])
                self.assertTrue(binding["reject_explicit_productivity_denial"])
                family = binding["family"]
                bindings.setdefault(family, []).extend((recipe, binding["weight"]) for recipe in binding["recipes"])
            for key, expected_recipes in delta["required_product_targets"].items():
                self.assertEqual(
                    set(recipe for recipe, _ in bindings[key]), set(expected_recipes), f"{capture_name}:{key}"
                )
            for family, recipes in bindings.items():
                technology = self.facts["captures"][capture_name]["technologies"][f"recipe-prod-{family}-1"]
                self.assertEffectsAlmostEqual(
                    _productivity_effects(technology, DEFINITION_EFFECT_PERCENT.get(family, 10)), recipes
                )
            self.assertEqual(delta["replacement_product_target_families"], {})
            self.assertEqual(delta["excluded_product_target_recipes"], {})

    def test_aai_presentation_boundary_and_inactive_modules_remain_literal(self):
        expected = ["research_engine", "research_electric_engine"]
        for delta in (self.se, self.k2se):
            self.assertNotIn("aai_owned_presentation", delta)
            self.assertNotIn("captured_source_data_raw_dump_sha256", delta)
        self.assertEqual(
            self.facts["aai_owned_presentation_names"],
            ["recipe-prod-research_engine-1", "recipe-prod-research_electric_engine-1"],
        )
        for delta in (self.se, self.k2se):
            for key in expected:
                self.assertNotIn("icons", delta["definition_overrides"].get(key, {}), key)
        for relative in (
            "source/compatibility/modern_catalogue/space_exploration.lua",
            "source/compatibility/modern_catalogue/k2_space_exploration.lua",
        ):
            source = (ROOT / relative).read_text(encoding="utf-8")
            self.assertNotIn("require(", source, relative)
            self.assertNotIn("data.raw", source, relative)
            self.assertNotIn("active_mods", source, relative)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SpaceExplorationCatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
