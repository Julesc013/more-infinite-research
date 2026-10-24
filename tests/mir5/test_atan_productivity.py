"""Bounded F200 ATAN Base/Space Age productivity adapter checks; no native claim."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
from historical_sources import read_published_source
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
FACTS_PATH = ROOT / "tests/mir5/fixtures/atan-f200-captured-facts.json"


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
            "amount_min": None,
            "amount_max": None,
            "probability": None,
            "independent_probability": None,
            "shared_probability": None,
            "catalyst_amount": None,
            "ignored_by_productivity": None,
            "extra_count_fraction": None,
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
        expected_probability = wanted.get("probability", "default")
        if (found["type"] != wanted["type"]
                or found["name"] != wanted["name"]
                or found["amount"] != wanted["amount"]
                or found["amount_min"] is not None
                or found["amount_max"] is not None
                or (found["probability"] not in (None, 1)
                    if expected_probability == "default"
                    else found["probability"] != expected_probability)
                or found["independent_probability"] not in (None, 1)
                or found["catalyst_amount"] not in (None, 0)
                or found["ignored_by_productivity"] not in (None, 0)
                or found["extra_count_fraction"] not in (None, 0)):
            return False
        shared = found["shared_probability"]
        if shared is not None and shared != {"min": 0, "max": 1}:
            return False
    return True


class AtanProductivityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        if cls.facts.get("kind") != "mir5-atan-f200-productivity-captured-facts":
            raise AssertionError("ATAN captured-fact fixture kind drifted")
        cls.variants = {"base": cls.facts, "space_age": cls.facts["space_age"]}
        evidence = cls.facts["authored_evidence"]
        read_published_source(ROOT, evidence["legacy_streams_path"], evidence["legacy_streams_sha256"])
        if _sha256(ROOT / evidence["historical_settings_path"]) != evidence["historical_settings_sha256"]:
            raise AssertionError("ATAN historical settings evidence changed")

        expected_ids = [
            "recipe-prod-research_air_scrubbing_clean_filter-1",
            "recipe-prod-research_ash_separation-1",
        ]
        for variant_name, variant in cls.variants.items():
            if len(variant["definitions"]) != 2 or len(variant["published_rows"]) != 2:
                raise AssertionError(f"F200 ATAN {variant_name} must retain two technology identities")
            if [row["name"] for row in variant["published_rows"]] != expected_ids:
                raise AssertionError(f"ATAN {variant_name} published identities drifted")
            profile = ROOT / variant["profile"]
            if _sha256(profile) != variant["profile_sha256"]:
                raise AssertionError(f"hash-locked ATAN {variant_name} input changed: {profile}")

            upstream = ROOT / variant["upstream_raw"]["path"]
            if upstream.is_file():
                if _sha256(upstream) != variant["upstream_raw"]["sha256"]:
                    raise AssertionError(f"captured upstream ATAN {variant_name} raw changed")
                cls._verify_local_upstream_raw(variant_name, variant, json.loads(upstream.read_text(encoding="utf-8")))

            published = ROOT / variant["published_raw"]["path"]
            if published.is_file():
                if _sha256(published) != variant["published_raw"]["sha256"]:
                    raise AssertionError(f"captured published ATAN {variant_name} raw changed")
                cls._verify_local_published_raw(variant_name, variant, json.loads(published.read_text(encoding="utf-8")))

    @classmethod
    def _verify_local_upstream_raw(cls, variant_name, variant, raw):
        for route in variant["routes"]:
            item = raw.get("item", {}).get(route["item"])
            if not isinstance(item, dict) or item.get("icon") != route["item_icon"]:
                raise AssertionError(f"captured ATAN {variant_name} presentation drifted: {route['item']}")
            if route["item_icon_size"] == "default":
                if item.get("icon_size") not in (None, 64):
                    raise AssertionError(f"captured ATAN {variant_name} default icon size drifted: {route['item']}")
            elif item.get("icon_size") != route["item_icon_size"]:
                raise AssertionError(f"captured ATAN {variant_name} icon size drifted: {route['item']}")

            recipe = raw.get("recipe", {}).get(route["recipe"])
            if (not isinstance(recipe, dict) or recipe.get("enabled") is not route["enabled"]
                    or recipe.get("hidden") is True
                    or recipe.get("category") != route["category"]
                    or recipe.get("energy_required") != route["energy_required"]
                    or (recipe.get("allow_productivity") is not None
                        if route["allow_productivity"] == "omitted"
                        else recipe.get("allow_productivity") != route["allow_productivity"])
                    or (recipe.get("maximum_productivity") is not None
                        if route["maximum_productivity"] == "omitted"
                        else recipe.get("maximum_productivity") != route["maximum_productivity"])
                    or not _ordinary_matches(recipe.get("ingredients"), route["ingredients"])
                    or not _ordinary_matches(recipe.get("results"), route["results"])):
                raise AssertionError(f"captured ATAN {variant_name} route drifted: {route['recipe']}")

            owner = raw.get("technology", {}).get(route["owner"])
            if (not isinstance(owner, dict) or owner.get("enabled") is False or owner.get("hidden") is True
                    or owner.get("prerequisites", []) != route["owner_prerequisites"]
                    or owner.get("unit", {}).get("count") != route["owner_count"]
                    or owner.get("unit", {}).get("time") != route["owner_time"]
                    or not _ordinary_matches(owner.get("unit", {}).get("ingredients"), route["owner_science"])):
                raise AssertionError(f"captured ATAN {variant_name} owner drifted: {route['owner']}")
            matching = [effect for effect in owner.get("effects", []) if effect.get("recipe") == route["recipe"]]
            if matching != route["owner_effects_for_route"]:
                raise AssertionError(f"captured ATAN {variant_name} owner unlock drifted: {route['owner']}")

        for name in variant.get("base_absent_recipes", []):
            if name in raw.get("recipe", {}):
                raise AssertionError(f"Base capture unexpectedly contains withheld route: {name}")

    @classmethod
    def _verify_local_published_raw(cls, variant_name, variant, raw):
        actual = raw.get("technology", {})
        for expected in variant["published_rows"]:
            if actual.get(expected["name"]) != expected:
                raise AssertionError(f"published ATAN {variant_name} technology drifted: {expected['name']}")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
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
        self.adapter = self.lua.execute('return require("compatibility.atan_productivity")')
        self.modern = self.lua.execute('return require("research.modern")')

    def variant(self, name):
        return self.variants[name]

    def active_mods(self, variant="base", names=None):
        selected = self.variant(variant)["required_mods"] if names is None else names
        return _lua_value(self.lua, selected)

    def raw_fixture(self, variant="base"):
        raw = {"item": {}, "recipe": {}, "technology": {}}
        for route in self.variant(variant)["routes"]:
            item = raw["item"][route["item"]] = {"icon": route["item_icon"]}
            if route["item_icon_size"] != "default":
                item["icon_size"] = route["item_icon_size"]
            recipe = raw["recipe"][route["recipe"]] = {
                "enabled": route["enabled"],
                "category": route["category"],
                "energy_required": route["energy_required"],
                "ingredients": deepcopy(route["ingredients"]),
                "results": deepcopy(route["results"]),
            }
            if route["allow_productivity"] != "omitted":
                recipe["allow_productivity"] = route["allow_productivity"]
            if route["maximum_productivity"] != "omitted":
                recipe["maximum_productivity"] = route["maximum_productivity"]
            raw["technology"][route["owner"]] = {
                "prerequisites": deepcopy(route["owner_prerequisites"]),
                "unit": {
                    "count": route["owner_count"], "time": route["owner_time"],
                    "ingredients": deepcopy(route["owner_science"]),
                },
                "effects": deepcopy(route["owner_effects_for_route"]),
            }
        return _lua_value(self.lua, raw)

    def select(self, variant="base", mods=None, raw=None):
        return self.adapter["select"](
            mods or self.active_mods(variant), raw or self.raw_fixture(variant)
        )

    def values(self, variant="base"):
        return _lua_value(self.lua, {
            "streams": {
                definition["family"]: deepcopy(definition["tuning"])
                for definition in self.variant(variant)["definitions"]
            },
            "options": {},
        })

    def emitted_rows(self, variant="base", mods=None, raw=None, values=None):
        definitions = self.select(variant, mods=mods, raw=raw)
        selection = self.lua.table()
        selection["definitions"] = definitions
        selection["continuations"] = self.lua.table()
        return self.modern["technologies"](selection, values or self.values(variant))

    def assert_definition_bindings(self, definitions, variant="base"):
        expected_variant = self.variant(variant)
        actual_definitions = _plain(definitions)
        self.assertEqual(len(expected_variant["definitions"]), len(actual_definitions))
        for actual, expected in zip(actual_definitions, expected_variant["definitions"]):
            bindings = actual.pop("bindings", None)
            if bindings is None:
                bindings = [actual.pop("binding")]
            self.assertEqual(expected, actual)
            effect_recipes = [effect["recipe"] for effect in expected["effects"]]
            expected_routes = [
                route for route in expected_variant["routes"] if route["recipe"] in effect_recipes
            ]
            self.assertEqual(len(expected_routes), len(bindings))
            for binding, route in zip(bindings, expected_routes):
                self.assertEqual(route["recipe"], binding["recipe"])
                self.assertEqual(route["owner"], binding["owner"])
                self.assertEqual(route["item"], binding.get("item", expected["item"]))
                self.assertEqual(route["item_icon"], binding.get("item_icon", expected["icon"]))
                self.assertEqual(route["item_icon_size"], binding["item_icon_size"])
                self.assertEqual(route["category"], binding["category"])
                self.assertEqual(route["energy_required"], binding["energy_required"])
                self.assertEqual(route["enabled"], binding["enabled"])
                self.assertEqual(route["maximum_productivity"], binding["maximum_productivity"])
                self.assertEqual(route["ingredients"], binding["ingredients"])
                self.assertEqual(route["results"], binding["results"])
                self.assertEqual(route["owner_prerequisites"], binding["owner_prerequisites"])
                self.assertEqual(route["owner_count"], binding["owner_unit_count"])
                self.assertEqual(route["owner_time"], binding["owner_unit_time"])
                self.assertEqual(route["owner_science"], binding["owner_science"])
                expected_permission = "not-false" if route["allow_productivity"] == "omitted" else route["allow_productivity"]
                self.assertEqual(expected_permission, binding["allow_productivity"])

    def test_base_pure_definitions_and_selected_rows_match_independent_facts(self):
        pure = self.lua.execute('return require("research.atan_productivity")')
        self.assert_definition_bindings(pure["f200_base_definitions"](), "base")

        fresh = pure["base_filter"]()
        fresh["effects"][1]["recipe"] = "corrupted"
        self.assertEqual("atan-pollution-filter", _plain(pure["base_filter"]())["effects"][0]["recipe"])

        rows = _plain(self.emitted_rows())
        self.assertEqual(self.facts["published_rows"], rows)
        self.assertEqual(2, len(rows))
        self.assertEqual(60, rows[0]["unit"]["time"])
        self.assertEqual(90, rows[1]["unit"]["time"])

    def test_changed_settings_apply_only_to_the_selected_families(self):
        values = self.values()
        filter_stream = values["streams"]["research_air_scrubbing_clean_filter"]
        filter_stream["base_cost"] = 125
        filter_stream["linear_increment"] = 3
        filter_stream["growth_factor"] = 1.5
        filter_stream["research_time"] = 45
        filter_stream["effect_percent"] = 7
        values["streams"]["research_ash_separation"]["enabled"] = False

        rows = _plain(self.emitted_rows(values=values))
        self.assertEqual("(125+3*(L-1))*1.5^(L-1)", rows[0]["unit"]["count_formula"])
        self.assertEqual(45, rows[0]["unit"]["time"])
        self.assertEqual(0.07, rows[0]["effects"][0]["change"])
        self.assertEqual("8000*2^(L-1)", rows[1]["unit"]["count_formula"])
        self.assertEqual(90, rows[1]["unit"]["time"])
        self.assertEqual(0.05, rows[1]["effects"][0]["change"])
        self.assertIs(False, rows[1]["enabled"])

    def test_f200_gates_do_not_load_inactive_bodies_or_admit_f210(self):
        self.lua.execute("f210()")
        self.assertEqual(0, len(self.select()))
        self.lua.execute("f200()")
        self.lua.execute('target.minimum_base = "2.0.78"')
        with self.assertRaisesRegex(Exception, "unsupported F200 ATAN saved-profile transition"):
            self.select()
        self.lua.execute('target.minimum_base = "2.0.77"')

        self.assertEqual(0, len(self.select(mods=self.active_mods(names={}))))
        base = _plain(self.emitted_rows("base"))
        self.assertEqual(base, _plain(self.emitted_rows("base", mods=self.active_mods(names={
            "atan-air-scrubbing": "wrong", "atan-ash": "wrong",
        }))))
        space_age = _plain(self.emitted_rows("space_age"))
        self.assertEqual(space_age, _plain(self.emitted_rows("space_age", mods=self.active_mods(names={
            "atan-air-scrubbing": "wrong", "atan-ash": "wrong", "space-age": "2.0.78",
        }))))
        changed_mods = self.active_mods(names={
            "atan-air-scrubbing": "wrong", "atan-ash": "wrong", "space-age": "2.0.78",
        })
        drifted = self.raw_fixture("space_age")
        drifted["technology"]["automation-3"]["unit"]["time"] = 61
        with self.assertRaisesRegex(Exception, "automation-3 no longer owns atan-ash-seperation"):
            self.emitted_rows("space_age", mods=changed_mods, raw=drifted)
        observer = {**self.facts["required_mods"], "unrelated-observer": "0.1.0"}
        self.assertEqual(2, len(self.select(mods=self.active_mods(names=observer))))

        # Each single-mod combination lacks the captured other half. Do not
        # promote an unobserved profile merely because one named route exists.
        self.assertEqual(0, len(self.select(mods=self.active_mods(names={"atan-air-scrubbing": "0.2.8"}))))
        self.assertEqual(0, len(self.select(mods=self.active_mods(names={"atan-ash": "2.2.1"}))))

        isolated = LuaRuntime(unpack_returned_tuples=True)
        isolated.globals().player_root = (ROOT / "source/mir5").as_posix()
        isolated.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          adapter = require("compatibility.atan_productivity")
        ''')
        self.assertEqual(0, len(isolated.globals().adapter["select"](isolated.table(), None)))
        self.assertIsNone(isolated.eval('package.loaded["research.atan_productivity"]'))

    def test_named_preflight_rejects_route_owner_and_safety_drift_without_scanning(self):
        poison = self.lua.eval(
            'function(value) return setmetatable(value, {__pairs=function() error("global scan") end}) end'
        )
        raw = self.raw_fixture()
        raw["item"] = poison(raw["item"])
        raw["recipe"] = poison(raw["recipe"])
        raw["technology"] = poison(raw["technology"])
        self.assertEqual(2, len(self.select(raw=raw)))

        presentation = self.raw_fixture()
        presentation["item"]["atan-pollution-filter"]["icon"] = "wrong"
        with self.assertRaisesRegex(Exception, "atan-pollution-filter presentation changed"):
            self.select(raw=presentation)

        category = self.raw_fixture()
        category["recipe"]["atan-pollution-filter"]["category"] = "chemistry"
        with self.assertRaisesRegex(Exception, "atan-pollution-filter changed"):
            self.select(raw=category)

        allowed_default = self.raw_fixture()
        allowed_default["recipe"]["atan-pollution-filter"]["allow_productivity"] = True
        self.assertEqual(2, len(self.select(raw=allowed_default)))
        forbidden_filter = self.raw_fixture()
        forbidden_filter["recipe"]["atan-pollution-filter"]["allow_productivity"] = False
        with self.assertRaisesRegex(Exception, "atan-pollution-filter changed"):
            self.select(raw=forbidden_filter)

        missing_ash_permission = self.raw_fixture()
        missing_ash_permission["recipe"]["atan-ash-seperation"]["allow_productivity"] = None
        with self.assertRaisesRegex(Exception, "atan-ash-seperation changed"):
            self.select(raw=missing_ash_permission)

        probability = self.raw_fixture()
        probability["recipe"]["atan-ash-seperation"]["results"][1]["probability"] = 0.1
        with self.assertRaisesRegex(Exception, "atan-ash-seperation changed"):
            self.select(raw=probability)

        catalyst = self.raw_fixture()
        catalyst["recipe"]["atan-ash-seperation"]["ingredients"][1]["catalyst_amount"] = 1
        with self.assertRaisesRegex(Exception, "atan-ash-seperation changed"):
            self.select(raw=catalyst)

        productivity_cap = self.raw_fixture()
        productivity_cap["recipe"]["atan-pollution-filter"]["maximum_productivity"] = 3
        with self.assertRaisesRegex(Exception, "atan-pollution-filter changed"):
            self.select(raw=productivity_cap)

        owner_time = self.raw_fixture()
        owner_time["technology"]["automation-3"]["unit"]["time"] = 61
        with self.assertRaisesRegex(Exception, "automation-3 no longer owns atan-ash-seperation"):
            self.select(raw=owner_time)

        duplicate_unlock = self.raw_fixture()
        duplicate_unlock["technology"]["atan-pollution-scrubbing"]["effects"][2] = {
            "type": "unlock-recipe", "recipe": "atan-pollution-filter",
        }
        with self.assertRaisesRegex(Exception, "atan-pollution-scrubbing no longer owns atan-pollution-filter"):
            self.select(raw=duplicate_unlock)

        foreign_effect = self.raw_fixture()
        foreign_effect["technology"]["automation-3"]["effects"][1]["type"] = "change-recipe-productivity"
        with self.assertRaisesRegex(Exception, "automation-3 no longer owns atan-ash-seperation"):
            self.select(raw=foreign_effect)

    def test_selected_definitions_are_detached_and_preserve_the_withheld_effect_boundary(self):
        first = self.select()
        first[1]["effects"][1]["recipe"] = "corrupted"
        first[2]["binding"]["owner_prerequisites"][1] = "corrupted"
        first[1]["localised_name"][2] = "corrupted"
        second = _plain(self.select())
        self.assertEqual(self.facts["definitions"], [
            {key: value for key, value in row.items() if key != "binding"}
            for row in second
        ])

        rows = _plain(self.emitted_rows())
        effects = {
            effect["recipe"]
            for row in rows for effect in row["effects"]
            if effect["type"] == "change-recipe-productivity"
        }
        self.assertEqual({route["recipe"] for route in self.facts["routes"]}, effects)
        self.assertTrue(effects.isdisjoint(self.facts["excluded_recipe_effects"]))
        self.assertNotIn("atan-spore-filter", effects)


    def test_space_age_pure_definitions_rows_and_settings_match_independent_facts(self):
        expected = self.variant("space_age")
        pure = self.lua.execute('return require("research.atan_productivity")')
        self.assert_definition_bindings(pure["f200_space_age_definitions"](), "space_age")

        fresh = pure["space_age_filter"]()
        fresh["bindings"][2]["owner"] = "corrupted"
        self.assertEqual("atan-spore-scrubbing", _plain(pure["space_age_filter"]())["bindings"][1]["owner"])

        rows = _plain(self.emitted_rows("space_age"))
        self.assertEqual(expected["published_rows"], rows)
        self.assertEqual(
            ["atan-pollution-filter", "atan-spore-filter"],
            [effect["recipe"] for effect in rows[0]["effects"]],
        )
        self.assertEqual(60, rows[0]["unit"]["time"])
        self.assertEqual(90, rows[1]["unit"]["time"])

        values = self.values("space_age")
        values["streams"]["research_air_scrubbing_clean_filter"]["effect_percent"] = 7
        values["streams"]["research_air_scrubbing_clean_filter"]["research_time"] = 45
        values["streams"]["research_ash_separation"]["enabled"] = False
        changed = _plain(self.emitted_rows("space_age", values=values))
        self.assertEqual([0.07, 0.07], [effect["change"] for effect in changed[0]["effects"]])
        self.assertEqual(45, changed[0]["unit"]["time"])
        self.assertEqual(0.05, changed[1]["effects"][0]["change"])
        self.assertEqual(90, changed[1]["unit"]["time"])
        self.assertIs(False, changed[1]["enabled"])

    def test_space_age_gate_and_named_preflight_preserve_the_variant_boundary(self):
        expected = self.variant("space_age")
        patched_space_age = dict(expected["required_mods"])
        patched_space_age["space-age"] = "2.0.78"
        self.assertEqual(expected["published_rows"], _plain(self.emitted_rows(
            "space_age", mods=self.active_mods("space_age", patched_space_age)
        )))
        observer = {**expected["required_mods"], "unrelated-observer": "0.1.0"}
        self.assertEqual(2, len(self.select(
            "space_age", mods=self.active_mods("space_age", observer)
        )))

        self.lua.execute("f210()")
        self.assertEqual(0, len(self.select("space_age")))
        self.lua.execute("f200()")

        poison = self.lua.eval(
            'function(value) return setmetatable(value, {__pairs=function() error("global scan") end}) end'
        )
        raw = self.raw_fixture("space_age")
        raw["item"] = poison(raw["item"])
        raw["recipe"] = poison(raw["recipe"])
        raw["technology"] = poison(raw["technology"])
        self.assertEqual(2, len(self.select("space_age", raw=raw)))

        carbon = self.raw_fixture("space_age")
        carbon["recipe"]["atan-pollution-filter"]["ingredients"][1]["name"] = "coal"
        with self.assertRaisesRegex(Exception, "atan-pollution-filter changed"):
            self.select("space_age", raw=carbon)

        spore_owner = self.raw_fixture("space_age")
        spore_owner["technology"]["atan-spore-scrubbing"]["prerequisites"][1] = "wrong"
        with self.assertRaisesRegex(Exception, "atan-spore-scrubbing no longer owns atan-spore-filter"):
            self.select("space_age", raw=spore_owner)

        ash_owner = self.raw_fixture("space_age")
        ash_owner["technology"]["automation-3"]["unit"]["count"] = 150
        with self.assertRaisesRegex(Exception, "automation-3 no longer owns atan-ash-seperation"):
            self.select("space_age", raw=ash_owner)

        spore_icon = self.raw_fixture("space_age")
        spore_icon["item"]["atan-spore-filter"]["icon"] = "wrong"
        with self.assertRaisesRegex(Exception, "atan-spore-filter presentation changed"):
            self.select("space_age", raw=spore_icon)

    def test_space_age_outputs_are_detached_and_keep_denied_routes_outside_effects(self):
        first = self.select("space_age")
        first[1]["bindings"][2]["owner"] = "corrupted"
        first[1]["effects"][2]["recipe"] = "corrupted"
        first[2]["binding"]["owner_unit_count"] = 150
        second = self.select("space_age")
        self.assert_definition_bindings(second, "space_age")

        rows = _plain(self.emitted_rows("space_age"))
        effects = {
            effect["recipe"]
            for row in rows for effect in row["effects"]
            if effect["type"] == "change-recipe-productivity"
        }
        expected = self.variant("space_age")
        self.assertEqual({route["recipe"] for route in expected["routes"]}, effects)
        self.assertTrue(effects.isdisjoint(expected["excluded_recipe_effects"]))



if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AtanProductivityTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
