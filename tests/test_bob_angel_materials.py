"""Bounded F200 Bob/Angel material constructor checks; no native claim."""
import argparse
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import sys
import unittest
from historical_sources import read_published_source


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/bob-angel-f200-captured-facts.json"
INVENTORY_PATH = ROOT / "spec/inventory/bob-angel-f200-472.json"

# These five source-compatible continuations deliberately become unbounded in
# MIR5. The independent 4.7.2 oracle still establishes every other field and
# the historical finite predecessor cap; runtime applies the per-family 3x
# productivity headroom as an effective cap.
REVIEWED_UNBOUNDED_TAILS = {
    "recipe-prod-research_material_aluminium-4": "infinite",
    "recipe-prod-research_material_copper_tungsten-4": "infinite",
    "recipe-prod-research_material_gold-4": "infinite",
    "recipe-prod-research_material_tin-4": "infinite",
    "recipe-prod-research_material_titanium-4": "infinite",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _lua_value(lua, value):
    if isinstance(value, dict):
        result = lua.table()
        for key, nested in value.items():
            result[key] = _lua_value(lua, nested)
        return result
    if isinstance(value, list):
        result = lua.table()
        for index, nested in enumerate(value, start=1):
            result[index] = _lua_value(lua, nested)
        return result
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(nested) for key, nested in values.items()}


def _entry(value):
    if isinstance(value, list):
        return {
            "type": "item",
            "name": value[0] if value else None,
            "amount": value[1] if len(value) > 1 else 1,
        }
    if not isinstance(value, dict):
        return {}
    return {
        "type": value.get("type", "item"),
        "name": value.get("name", value.get(1)),
        "amount": value.get("amount", value.get(2)),
        "amount_min": value.get("amount_min"),
        "amount_max": value.get("amount_max"),
        "probability": value.get("probability"),
        "independent_probability": value.get("independent_probability"),
        "shared_probability": value.get("shared_probability"),
        "catalyst_amount": value.get("catalyst_amount"),
        "ignored_by_productivity": value.get("ignored_by_productivity"),
        "extra_count_fraction": value.get("extra_count_fraction"),
    }


def _ordinary_matches(actual, expected):
    if not isinstance(actual, list) or len(actual) != len(expected):
        return False
    for found, wanted in zip(actual, expected):
        found = _entry(found)
        if (found.get("type") != wanted["type"]
                or found.get("name") != wanted["name"]
                or found.get("amount") != wanted["amount"]
                or found.get("amount_min") is not None
                or found.get("amount_max") is not None
                or found.get("probability") not in (None, 1)
                or found.get("independent_probability") not in (None, 1)
                or found.get("catalyst_amount") not in (None, 0)
                or found.get("ignored_by_productivity") not in (None, 0)
                or found.get("extra_count_fraction") not in (None, 0)):
            return False
        shared = found.get("shared_probability")
        if shared is not None and shared != {"min": 0, "max": 1}:
            return False
    return True


class BobAngelMaterialTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
        try:
            additions = inventory["profiles"][0]["published_output"]["data"]["additions"]
        except (IndexError, KeyError, TypeError) as error:
            raise AssertionError("independent Bob/Angel published output is unavailable") from error
        cls.published_default_rows = [
            deepcopy(entry["row"])
            for entry in additions
            if entry.get("name", "").startswith("recipe-prod-research_material_")
        ]
        if len(cls.published_default_rows) != 10:
            raise AssertionError("independent Bob/Angel oracle must contain exactly ten material rows")
        default_names = [row["name"] for row in cls.published_default_rows]
        if len(default_names) != len(set(default_names)):
            raise AssertionError("independent Bob/Angel material IDs must be unique")
        if set(REVIEWED_UNBOUNDED_TAILS) - set(default_names):
            raise AssertionError("reviewed MIR5 tail difference is absent from the independent oracle")
        cls.expected_rows = deepcopy(cls.published_default_rows)
        for row in cls.expected_rows:
            reviewed_maximum = REVIEWED_UNBOUNDED_TAILS.get(row["name"])
            if reviewed_maximum is not None:
                if row.get("max_level") != 150:
                    raise AssertionError(f"published tail cap drifted: {row['name']}")
                row["max_level"] = reviewed_maximum
            elif row.get("max_level") != 3:
                raise AssertionError(f"published early cap drifted: {row['name']}")
        cls.withheld_families = tuple(cls.facts["withheld_families"])
        if len(cls.withheld_families) != 11:
            raise AssertionError("Bob/Angel material withholding must retain exactly eleven families")
        captured_tail_ids = set()
        for family in cls.facts["selected_families"]:
            if (family.get("productivity_ceiling") != 3
                    or family["early"].get("max_level") != 3
                    or family["continuation"].get("max_level") != 150):
                raise AssertionError(f"captured material cap facts drifted: {family['key']}")
            captured_tail_ids.add(family["continuation"]["id"])
            for route in family["routes"]:
                if route.get("maximum_productivity") not in ("omitted", 3, 3.0):
                    raise AssertionError(f"captured recipe productivity cap drifted: {route['recipe']}")
        if captured_tail_ids != set(REVIEWED_UNBOUNDED_TAILS):
            raise AssertionError("reviewed MIR5 tails no longer match captured material continuations")

        profile = ROOT / cls.facts["profile"]
        if _sha256(profile) != cls.facts["profile_sha256"]:
            raise AssertionError(f"hash-locked Bob/Angel input changed: {profile}")
        source = cls.facts["authored_selector_evidence"]
        read_published_source(ROOT, source["path"], source["sha256"])

        cls.upstream_raw_path = ROOT / cls.facts["upstream_raw"]["path"]
        if cls.upstream_raw_path.is_file():
            if _sha256(cls.upstream_raw_path) != cls.facts["upstream_raw"]["sha256"]:
                raise AssertionError("captured upstream Bob/Angel raw changed")
            cls._verify_local_upstream_raw(json.loads(cls.upstream_raw_path.read_text(encoding="utf-8")))

        cls.published_raw_path = ROOT / cls.facts["published_raw"]["path"]
        if cls.published_raw_path.is_file():
            if _sha256(cls.published_raw_path) != cls.facts["published_raw"]["sha256"]:
                raise AssertionError("captured published Bob/Angel raw changed")
            cls._verify_local_published_raw(json.loads(cls.published_raw_path.read_text(encoding="utf-8")))

    @classmethod
    def _verify_local_upstream_raw(cls, raw):
        for family in cls.facts["selected_families"]:
            item = raw.get("item", {}).get(family["item"])
            if not isinstance(item, dict) or item.get("icon") != family["icon"] or item.get("icon_size") != family["icon_size"]:
                raise AssertionError(f"captured material presentation drifted: {family['item']}")
            for route in family["routes"]:
                recipe = raw.get("recipe", {}).get(route["recipe"])
                if (not isinstance(recipe, dict) or recipe.get("enabled") is not False
                        or recipe.get("hidden") is True or recipe.get("allow_productivity") is not True
                        or (recipe.get("maximum_productivity") is not None
                            if route["maximum_productivity"] == "omitted"
                            else recipe.get("maximum_productivity") != route["maximum_productivity"])
                        or not _ordinary_matches(recipe.get("ingredients"), route["ingredients"])
                        or not _ordinary_matches(recipe.get("results"), route["results"])):
                    raise AssertionError(f"captured route drifted: {route['recipe']}")

                owner = raw.get("technology", {}).get(route["owner"])
                if not isinstance(owner, dict) or owner.get("enabled") is False:
                    raise AssertionError(f"captured owner missing: {route['owner']}")
                if owner.get("prerequisites", []) != route["owner_prerequisites"]:
                    raise AssertionError(f"captured owner prerequisites drifted: {route['owner']}")
                if not _ordinary_matches(owner.get("unit", {}).get("ingredients"), route["owner_science"]):
                    raise AssertionError(f"captured owner science drifted: {route['owner']}")
                matching = [effect for effect in owner.get("effects", []) if effect.get("recipe") == route["recipe"]]
                if sum(effect.get("type") == "unlock-recipe" for effect in matching) != 1:
                    raise AssertionError(f"captured owner unlock drifted: {route['owner']}")
                if any(effect.get("type") == "change-recipe-productivity" for effect in matching):
                    raise AssertionError(f"captured owner productivity drifted: {route['owner']}")

            for stage_name in ("early", "continuation"):
                for prerequisite in family[stage_name]["prerequisites"]:
                    if prerequisite != family["early"]["id"] and prerequisite not in raw.get("technology", {}):
                        raise AssertionError(f"captured prerequisite missing: {prerequisite}")

        for science in cls.facts["standard_science"]:
            if not isinstance(raw.get("tool", {}).get(science), dict):
                raise AssertionError(f"captured science pack missing: {science}")
        lab = raw.get("lab", {}).get(cls.facts["lab"]["name"])
        if not isinstance(lab, dict) or lab.get("inputs") != cls.facts["lab"]["inputs"]:
            raise AssertionError("captured Bob/Angel lab inputs drifted")

    @classmethod
    def _verify_local_published_raw(cls, raw):
        rows = cls.published_default_rows
        actual = raw.get("technology", {})
        names = [row["name"] for row in rows]
        if len(names) != len(set(names)):
            raise AssertionError("published material fact IDs must be unique")
        for row in rows:
            if actual.get(row["name"]) != row:
                raise AssertionError(f"published material technology drifted: {row['name']}")
        emitted = sorted(name for name in actual if name.startswith("recipe-prod-research_material_"))
        if emitted != sorted(names):
            raise AssertionError("published F200 material output added or lost an identity")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          function f200()
            target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
            target.distribution_version, target.cargo_research = "5.0.20000", false
            target.recipe_probability, target.receiver_limits = "probability", false
            target.productivity_ignores_stats = true
          end
          function f210()
            target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
            target.distribution_version, target.cargo_research = "5.0.21000", true
            target.recipe_probability, target.receiver_limits = "independent_probability", true
            target.productivity_ignores_stats = false
          end
          f200()
        ''')
        self.catalogue = self.lua.execute('return require("compatibility.bob_angel_materials")')
        self.generator = self.lua.execute('return require("research.generator")')

    def active_mods(self):
        return _lua_value(self.lua, self.facts["required_mods"])

    def values(self):
        streams = {
            family["key"]: {
                "enabled": True,
                "base_cost": 200,
                "linear_increment": 0,
                "growth_factor": 2,
                "research_time": 30,
                "effect_percent": 2,
            }
            for family in self.facts["selected_families"]
        }
        return _lua_value(self.lua, {"streams": streams})

    def raw_fixture(self):
        raw = {
            "item": {},
            "tool": {name: {} for name in self.facts["standard_science"]},
            "recipe": {},
            "technology": {},
            "lab": {self.facts["lab"]["name"]: deepcopy({"inputs": self.facts["lab"]["inputs"]})},
        }
        for family in self.facts["selected_families"]:
            raw["item"][family["item"]] = {
                "icon": family["icon"],
                "icon_size": family["icon_size"],
            }
            for route in family["routes"]:
                recipe = raw["recipe"][route["recipe"]] = {
                    "enabled": False,
                    "allow_productivity": True,
                    "ingredients": deepcopy(route["ingredients"]),
                    "results": deepcopy(route["results"]),
                }
                if route["maximum_productivity"] != "omitted":
                    recipe["maximum_productivity"] = route["maximum_productivity"]
                owner = raw["technology"].setdefault(route["owner"], {
                    "prerequisites": deepcopy(route["owner_prerequisites"]),
                    "unit": {"ingredients": deepcopy(route["owner_science"])},
                    "effects": [],
                })
                self.assertEqual(route["owner_prerequisites"], owner["prerequisites"])
                self.assertEqual(route["owner_science"], owner["unit"]["ingredients"])
                owner["effects"].append({"type": "unlock-recipe", "recipe": route["recipe"]})

            for stage in (family["early"], family["continuation"]):
                for name in stage["prerequisites"]:
                    if name != family["early"]["id"]:
                        raw["technology"].setdefault(name, {})
        return _lua_value(self.lua, raw)

    def rows(self, values=None, raw=None, mods=None):
        return self.catalogue["technologies"](
            values or self.values(),
            raw or self.raw_fixture(),
            mods or self.active_mods(),
        )

    def test_independent_published_rows_are_emitted_once_with_only_reviewed_tail_difference(self):
        rows = self.rows()
        actual = _plain(rows)
        self.assertEqual(self.expected_rows, actual)
        self.assertEqual(self.facts["totals"]["technology_rows"], len(actual))

        names = [row["name"] for row in actual]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(
            [row["name"] for row in self.expected_rows],
            names,
        )
        for withheld in self.withheld_families:
            self.assertNotIn(f"recipe-prod-{withheld['key']}-1", names)
            self.assertNotIn(f"recipe-prod-{withheld['key']}-4", names)

        raw = self.raw_fixture()
        self.lua.globals().fixture_raw = raw
        stage = self.lua.execute(r'''
          local stage = {raw = fixture_raw, writes = 0}
          function stage:extend(batch)
            self.writes = self.writes + 1
            self.batch = batch
          end
          return stage
        ''')
        self.generator["install"](rows, stage)
        self.assertEqual(1, stage["writes"])
        self.assertEqual(self.expected_rows, _plain(stage["batch"]))

    def test_changed_settings_preserve_the_staged_cost_and_effect_contract(self):
        values = self.values()
        aluminium = values["streams"]["research_material_aluminium"]
        aluminium["base_cost"] = 250
        aluminium["linear_increment"] = 3
        aluminium["growth_factor"] = 2
        aluminium["research_time"] = 45
        aluminium["effect_percent"] = 3
        values["streams"]["research_material_tin"]["enabled"] = False

        rows = _plain(self.rows(values=values))
        aluminium_early, aluminium_tail = rows[0], rows[1]
        self.assertEqual("(250+3*(L-1))*2^(L-1)", aluminium_early["unit"]["count_formula"])
        self.assertEqual("2072+250*(L-4)", aluminium_tail["unit"]["count_formula"])
        self.assertEqual(45, aluminium_early["unit"]["time"])
        self.assertEqual(45, aluminium_tail["unit"]["time"])
        self.assertEqual(0.03, aluminium_early["effects"][0]["change"])
        self.assertEqual(0.03, aluminium_tail["effects"][0]["change"])

        tin_early, tin_tail = rows[6], rows[7]
        self.assertIs(tin_early["enabled"], False)
        self.assertIs(tin_tail["enabled"], False)
        self.assertEqual(3, tin_early["max_level"])
        self.assertEqual("infinite", tin_tail["max_level"])

        invalid = self.values()
        invalid["streams"]["research_material_gold"]["effect_percent"] = float("inf")
        with self.assertRaisesRegex(Exception, "research_material_gold resolved settings are invalid"):
            self.rows(values=invalid)

    def test_pure_definition_ceiling_preserves_effect_headroom_without_prototype_truncation(self):
        definitions = _plain(self.lua.execute('return require("research.bob_angel_materials")'))
        self.assertEqual(5, len(definitions))
        self.assertEqual(
            {row["name"] for row in self.expected_rows},
            {
                stage["id"]
                for definition in definitions
                for stage in (definition["early"], definition["continuation"])
            },
        )
        self.assertTrue(all(definition["productivity_ceiling"] == 3 for definition in definitions))
        self.assertTrue(all(definition["early"]["max_level"] == 3 for definition in definitions))
        self.assertTrue(all(definition["continuation"]["max_level"] == "infinite" for definition in definitions))

        def useful_level_headroom(effect_percent):
            return math.ceil(3 * 100 / effect_percent)

        self.assertEqual(100, useful_level_headroom(3))
        self.assertEqual(300, useful_level_headroom(1))
        self.assertEqual(2, min(2, useful_level_headroom(3)))
        self.assertEqual(40, min(40, useful_level_headroom(3)))

    def test_gate_admits_changed_versions_only_with_the_same_raw_contract(self):
        self.assertEqual(10, len(self.rows()))
        self.lua.execute("f210()")
        self.assertEqual(0, len(self.rows()))
        self.lua.execute("f200()")

        baseline = _plain(self.rows())
        for changed in ("base", "bobplates", "angelssmeltinggraphics"):
            mods = dict(self.facts["required_mods"])
            mods[changed] = "different"
            self.assertEqual(baseline, _plain(self.rows(mods=_lua_value(self.lua, mods))))

        changed = dict(self.facts["required_mods"])
        changed["bobplates"] = "different"
        drifted = self.raw_fixture()
        drifted["recipe"]["angels-plate-gold"]["results"][1]["amount"] = 2
        with self.assertRaisesRegex(Exception, "angels-plate-gold changed"):
            self.rows(raw=drifted, mods=_lua_value(self.lua, changed))
        for forbidden in self.facts["forbidden_mods"]:
            mods = dict(self.facts["required_mods"])
            mods[forbidden] = "present"
            with self.assertRaisesRegex(Exception, "unsupported F200 Bob/Angel saved-profile transition"):
                self.rows(mods=_lua_value(self.lua, mods))

        partial = dict(self.facts["required_mods"])
        del partial["angelssmelting"]
        self.assertEqual(0, len(self.rows(mods=_lua_value(self.lua, partial))))
        unrelated = {**self.facts["required_mods"], "unrelated-observer": "0.1.0"}
        self.assertEqual(10, len(self.rows(mods=_lua_value(self.lua, unrelated))))

    def test_named_preflight_rejects_drift_without_a_global_scan_or_write(self):
        poison = self.lua.eval(
            'function(value) return setmetatable(value, {__pairs=function() error("global scan") end}) end'
        )
        raw = self.raw_fixture()
        raw["recipe"] = poison(raw["recipe"])
        raw["technology"] = poison(raw["technology"])
        self.assertEqual(10, len(self.rows(raw=raw)))

        presentation = self.raw_fixture()
        presentation["item"]["bob-aluminium-plate"]["icon"] = "wrong"
        with self.assertRaisesRegex(Exception, "bob-aluminium-plate presentation changed"):
            self.rows(raw=presentation)

        route = self.raw_fixture()
        route["recipe"]["angels-plate-gold"]["results"][1]["amount"] = 5
        with self.assertRaisesRegex(Exception, "angels-plate-gold changed"):
            self.rows(raw=route)

        typed_route = self.raw_fixture()
        typed_route["recipe"]["angels-plate-aluminium"]["ingredients"][1]["type"] = "item"
        with self.assertRaisesRegex(Exception, "angels-plate-aluminium changed"):
            self.rows(raw=typed_route)

        catalyst_input = self.raw_fixture()
        catalyst_input["recipe"]["angels-plate-aluminium"]["ingredients"][1]["catalyst_amount"] = 1
        with self.assertRaisesRegex(Exception, "angels-plate-aluminium changed"):
            self.rows(raw=catalyst_input)

        catalyst_result = self.raw_fixture()
        catalyst_result["recipe"]["angels-plate-aluminium"]["results"][1]["catalyst_amount"] = 1
        with self.assertRaisesRegex(Exception, "angels-plate-aluminium changed"):
            self.rows(raw=catalyst_result)

        productivity_cap = self.raw_fixture()
        productivity_cap["recipe"]["angels-plate-aluminium"]["maximum_productivity"] = 3
        with self.assertRaisesRegex(Exception, "angels-plate-aluminium changed"):
            self.rows(raw=productivity_cap)

        owner = self.raw_fixture()
        owner["technology"]["angels-tin-smelting-1"]["effects"][1]["type"] = "change-recipe-productivity"
        with self.assertRaisesRegex(Exception, "angels-tin-smelting-1 no longer owns angels-plate-tin"):
            self.rows(raw=owner)

        late_route = self.raw_fixture()
        late_route["recipe"]["angels-plate-titanium-2"]["results"][1]["amount"] = 5
        with self.assertRaisesRegex(Exception, "angels-plate-titanium-2 changed"):
            self.rows(raw=late_route)
        for row in self.expected_rows:
            self.assertIsNone(late_route["technology"][row["name"]])

    def test_outputs_are_detached_and_withheld_families_cannot_arrive_by_name(self):
        first = self.rows()
        first[1]["effects"][1]["recipe"] = "corrupted"
        first[2]["prerequisites"][1] = "corrupted"
        first[1]["icons"][1]["icon"] = "corrupted"
        second = _plain(self.rows())
        self.assertEqual(self.expected_rows, second)

        admitted_effects = {
            effect["recipe"]
            for row in second
            for effect in row["effects"]
            if effect["type"] == "change-recipe-productivity"
        }
        self.assertEqual(
            {
                route["recipe"]
                for family in self.facts["selected_families"]
                for route in family["routes"]
            },
            admitted_effects,
        )
        self.assertNotIn("bob-aluminium-plate", admitted_effects)
        self.assertNotIn("bob-gold-plate", admitted_effects)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobAngelMaterialTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
