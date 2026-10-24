"""Captured F200 armor/Py authoring and bounded collector checks; no native claim."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"
FACTS = ROOT / "tests/fixtures/armor-py-f200-472-recovered-facts.json"


def _lua_value(lua, value):
    if isinstance(value, dict):
        result = lua.table()
        for key, nested in value.items():
            result[key] = _lua_value(lua, nested)
        return result
    if isinstance(value, list):
        result = lua.table()
        for index, nested in enumerate(value, 1):
            result[index] = _lua_value(lua, nested)
        return result
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(item) for key, item in values.items()}


def _entry(entry):
    if isinstance(entry, list):
        return {"type": "item", "name": entry[0], "amount": entry[1]}
    return deepcopy(entry)


class ArmorPyCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        document = json.loads(FACTS.read_text(encoding="utf-8"))
        cls.profiles = {profile["id"]: profile for profile in document["profiles"]}
        if document.get("status") != "hash-verified-published-data-stage-reference-only":
            raise AssertionError("armor/Py facts do not state their limited captured status")
        if set(cls.profiles) != {"armor-bobwarfare", "py-coal", "py-alienlife-hightech"}:
            raise AssertionError("armor/Py fact profiles drifted")
        expected = {
            "armor-bobwarfare": {"recipe-prod-research_armor_components-1"},
            "py-coal": {"recipe-prod-research_material_py_log-1", "recipe-prod-research_material_py_log-4"},
            "py-alienlife-hightech": {
                "recipe-prod-research_breeding-1",
                "recipe-prod-research_supercapacitor-1",
                "recipe-prod-research_superconductor-1",
            },
        }
        for identifier, names in expected.items():
            observed = {
                row["name"]
                for rows in cls.profiles[identifier]["named_rows"].values()
                for row in rows
            }
            if observed != names:
                raise AssertionError(f"captured row set drifted for {identifier}")
        bob = cls.profiles["armor-bobwarfare"]
        vectors = bob.get("published_bob_warfare_effect_vectors")
        if not isinstance(vectors, dict) or vectors.get("source", {}).get("capture") != "published":
            raise AssertionError("Bob Warfare effect vectors lack their published-capture source")
        if vectors["source"].get("data_raw") != bob["capture_receipts"]["published"]["files"]["data_raw"]:
            raise AssertionError("Bob Warfare effect vectors do not bind the published raw receipt")
        rows = vectors.get("rows")
        if not isinstance(rows, list) or {row.get("name") for row in rows} != {
            "recipe-prod-research_bullets-1", "recipe-prod-research_rockets-1",
        } or any(not isinstance(row.get("effects"), list) or not row["effects"] for row in rows):
            raise AssertionError("Bob Warfare captured effect vectors drifted")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.productivity_ignores_stats, target.receiver_limits = "probability", true, false
        ''')
        self.catalogue = self.lua.execute('return require("compatibility.modern_catalogue")')
        self.modern = self.lua.execute('return require("research.modern")')
        self.extension = self.lua.execute('return require("research.product_target_extension")')
        self.science = self.lua.execute('return require("research.science")')
        self.py_materials = self.lua.execute('return require("compatibility.py_materials")')
        self.py_hightech = self.lua.execute('return require("compatibility.modern_catalogue.py")')
        self.armor = self.lua.execute('return require("compatibility.modern_catalogue.bob_warfare")')

    @staticmethod
    def active(identifier):
        if identifier == "armor-bobwarfare":
            return {"base": "2.0.77", "boblibrary": "2.1.0", "bobwarfare": "2.1.0"}
        if identifier == "py-coal":
            return {"base": "2.0.77", "pycoalprocessing": "3.0.44"}
        if identifier == "py-alienlife-hightech":
            return {
                "base": "2.0.77", "pycoalprocessing": "3.0.44",
                "pyalienlife": "3.0.67", "pyhightech": "3.0.19",
            }
        raise AssertionError(identifier)

    def _owner(self, route):
        owner = route["owners"][0]
        return {
            "enabled": True,
            "prerequisites": owner["prerequisites"],
            "unit": deepcopy(owner["unit"]),
            "effects": [{"type": "unlock-recipe", "recipe": route["name"]}],
        }

    def _raw(self, identifier):
        profile = self.profiles[identifier]
        raw = {"item": {}, "recipe": {}, "technology": {}, "tool": {}, "lab": {}}
        for pack in (
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
            "production-science-pack", "military-science-pack", "utility-science-pack",
            "space-science-pack",
        ):
            raw["tool"][pack] = {}
            raw["technology"][pack] = {}
        if identifier == "py-alienlife-hightech":
            for pack in ("py-science-pack-1", "py-science-pack-2", "py-science-pack-3",
                         "py-science-pack-4", "random-science-pack"):
                raw["tool"][pack] = {}
                raw["technology"][pack] = {}
        raw["lab"][profile["lab"]["name"]] = {
            "inputs": deepcopy(profile["lab"]["inputs"]),
            "researching_speed": profile["lab"]["researching_speed"],
        }
        for route in profile["effect_recipes"]:
            for item in route.get("product_facts", []):
                raw["item"][item["name"]] = {
                    "icon": item.get("icon"), "icon_size": item.get("icon_size"),
                }
            recipe = {
                "enabled": route["enabled"],
                "ingredients": deepcopy(route["ingredients"]),
                "results": deepcopy(route["results"]),
            }
            if "maximum_productivity" in route:
                recipe["maximum_productivity"] = route["maximum_productivity"]
            allow = route["allow_productivity"]
            if allow["present"]:
                recipe["allow_productivity"] = allow["value"]
            raw["recipe"][route["name"]] = recipe
            for owner in route["owners"]:
                raw["technology"][owner["technology"]] = {
                    "enabled": True,
                    "prerequisites": deepcopy(owner["prerequisites"]),
                    "unit": deepcopy(owner["unit"]),
                    "effects": [{"type": "unlock-recipe", "recipe": route["name"]}],
                }
        return raw

    def _values(self, active):
        self.lua.globals().mods = _lua_value(self.lua, active)
        settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
        return settings["resolve"](self.lua.table(), None, None)

    def _modern_rows(self, identifier):
        active = self.active(identifier)
        selection = self.catalogue["select"](_lua_value(self.lua, active))
        values = self._values(active)
        raw = self._raw(identifier)
        rows = self.modern["technologies"](selection, values)
        context = _lua_value(self.lua, {
            "raw": raw,
            "mods": active,
            "required_product_targets": _plain(selection["required_product_targets"]),
            "additional_product_bindings": _plain(selection["additional_product_bindings"]),
            "exact_product_bindings": _plain(selection["exact_product_bindings"]),
            "exact_product_target_families": _plain(selection["exact_product_target_families"]),
            "replacement_product_target_families": _plain(selection["replacement_product_target_families"]),
            "excluded_product_target_recipes": _plain(selection["excluded_product_target_recipes"]),
        })
        self.extension["extend"](rows, values, context)
        self.science["apply_family"](rows, None, _lua_value(self.lua, {
            "raw": raw, "options": _plain(values["options"]), "target": {},
            "mods": active,
        }))
        return _plain(rows), raw, values, selection

    def _expected_rows(self, identifier):
        return {
            row["name"]: deepcopy(row)
            for rows in self.profiles[identifier]["named_rows"].values()
            for row in rows
        }

    def _data_final_rows(self, identifier, raw=None):
        active = self.active(identifier)
        values = _plain(self._values(active))
        # Data-final still publishes retained identities when a stream is
        # disabled; suppress only the unrelated gear binding in this focused
        # harness, whose named raw route is outside these three captures.
        values["enabled"] = False
        values["options"] = values.get("options", {})
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().player_root = PLAYER.as_posix()
        runtime.globals().mods = _lua_value(runtime, active)
        runtime.globals().fixture_raw = _lua_value(runtime, raw or self._raw(identifier))
        runtime.globals().fixture_values = _lua_value(runtime, values)
        runtime.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.productivity_ignores_stats, target.receiver_limits = "probability", true, false
          data = {raw=fixture_raw, writes=0}
          settings, helpers, log = {startup={}}, {}, function() end
          package.preload["research.settings"] = function()
            return {resolve=function() return fixture_values end, default_value=function() return nil end}
          end
          local productivity = require("research.productivity")
          productivity.gears = function()
            return {type="technology", name="fixture-gears", unit={time=1, ingredients={{"automation-science-pack", 1}}}}
          end
          package.preload["research.generator"] = function()
            return {install=function(rows, stage) stage.writes = stage.writes + 1; stage.installed = rows end}
          end
          package.preload["research.native_credit_definitions"] = function() return {append=function() end} end
          -- The continuation adapter has its own named-predecessor harness.
          -- This data-final boundary check only proves its selected preflight
          -- remains before the single publication write.
          package.preload["compatibility.native_modded_continuations"] = function()
            return {
              continuation_overrides=function() return {} end,
              preflight=function()
                data.native_continuation_preflights = (data.native_continuation_preflights or 0) + 1
                return true
              end,
            }
          end
          require("data-final-fixes")
        ''')
        return (
            _plain(runtime.globals().data["installed"]),
            runtime.globals().data["writes"],
            runtime.globals().data["native_continuation_preflights"] or 0,
        )

    def test_captured_rows_match_the_bounded_modern_and_material_outputs(self):
        rows, _, _, _ = self._modern_rows("armor-bobwarfare")
        observed = {row["name"]: row for row in rows if row["name"] == "recipe-prod-research_armor_components-1"}
        self.assertEqual(self._expected_rows("armor-bobwarfare"), observed)

        rows, _, _, _ = self._modern_rows("py-alienlife-hightech")
        expected = self._expected_rows("py-alienlife-hightech")
        observed = {row["name"]: row for row in rows if row["name"] in expected}
        self.assertEqual(expected, observed)

        active = self.active("py-coal")
        values, raw = self._values(active), self._raw("py-coal")
        rows = _plain(self.py_materials["technologies"](values, _lua_value(self.lua, raw), _lua_value(self.lua, active)))
        self.assertEqual(self._expected_rows("py-coal"), {row["name"]: row for row in rows})

    def test_data_final_preflights_the_complete_selected_batch_then_publishes_once(self):
        for identifier in self.profiles:
            installed, writes, continuation_preflights = self._data_final_rows(identifier)
            observed = {row["name"]: row for row in installed if row["name"] in self._expected_rows(identifier)}
            self.assertEqual(self._expected_rows(identifier), observed)
            self.assertEqual(1, writes)
            self.assertEqual(1, continuation_preflights)

        bad = self._raw("py-alienlife-hightech")
        bad["recipe"]["arqad-mk02-breeding"]["allow_productivity"] = False
        with self.assertRaisesRegex(Exception, "breeding route changed"):
            self._data_final_rows("py-alienlife-hightech", bad)

    def test_hightech_routes_are_collected_once_and_exactly(self):
        rows, _, _, selection = self._modern_rows("py-alienlife-hightech")
        breeding = next(row for row in rows if row["name"] == "recipe-prod-research_breeding-1")
        expected = self._expected_rows("py-alienlife-hightech")[breeding["name"]]
        self.assertEqual(expected["effects"], breeding["effects"])
        self.assertEqual(33, len(breeding["effects"]))
        self.assertEqual(
            _plain(selection["required_product_targets"])["research_breeding"],
            [effect["recipe"] for effect in breeding["effects"]],
        )
        self.assertEqual(
            [
                {"family": "research_supercapacitor", "weight": 1,
                 "products": [{"type": "item", "name": "supercapacitor"}]},
                {"family": "research_superconductor", "weight": 1,
                 "products": [{"type": "item", "name": "superconductor"}]},
                {"family": "research_science_pack_productivity", "weight": 1,
                 "reject_explicit_productivity_denial": True,
                 "products": [
                     {"type": "item", "name": "automation-science-pack"},
                     {"type": "item", "name": "chemical-science-pack"},
                     {"type": "item", "name": "logistic-science-pack"},
                     {"type": "item", "name": "military-science-pack"},
                     {"type": "item", "name": "production-science-pack"},
                     {"type": "item", "name": "py-science-pack-1"},
                     {"type": "item", "name": "py-science-pack-2"},
                     {"type": "item", "name": "py-science-pack-3"},
                     {"type": "item", "name": "py-science-pack-4"},
                     {"type": "item", "name": "random-science-pack"},
                     {"type": "item", "name": "space-science-pack"},
                     {"type": "item", "name": "utility-science-pack"},
                 ]},
            ],
            _plain(selection["additional_product_bindings"]),
        )

    def test_py_normal_delta_rebuilds_only_named_vectors_and_withholds_known_base_routes(self):
        active = self.active("py-alienlife-hightech")
        values = self._values(active)
        selection = self.catalogue["select"](_lua_value(self.lua, active))
        definitions = {row["key"]: _plain(row) for row in selection["definitions"].values()}
        self.assertNotIn("research_oil_processing_productivity", definitions)
        self.assertNotIn("research_oil_cracking_productivity", definitions)
        self.assertEqual(
            "science_automation_logistic_chemical_production_space",
            definitions["research_belts"]["science"],
        )
        self.assertEqual(
            "science_automation_logistic_chemical_production_military_utility_space_py",
            definitions["research_science_pack_productivity"]["science"],
        )

        rows = _lua_value(self.lua, [
            {"name": "recipe-prod-research_batteries-1", "effects": [
                {"type": "change-recipe-productivity", "recipe": "battery", "change": 0.1},
            ]},
            {"name": "recipe-prod-research_sulfur-1", "effects": [
                {"type": "change-recipe-productivity", "recipe": "sulfur", "change": 0.1},
            ]},
        ])
        raw = _lua_value(self.lua, {"recipe": {
            "battery": {"ingredients": [], "results": [{"type": "item", "name": "battery", "amount": 1}]},
            "nas-battery": {"ingredients": [], "results": [{"type": "item", "name": "battery", "amount": 1}]},
            "sulfur": {"ingredients": [], "results": [{"type": "item", "name": "sulfur", "amount": 1}]},
            "aromatics-to-lubricant": {"ingredients": [], "results": [{"type": "item", "name": "sulfur", "amount": 1}]},
            "extract-sulfur": {"ingredients": [], "results": [{"type": "item", "name": "sulfur", "amount": 1}]},
        }, "module": {}})
        self.extension["extend"](rows, values, _lua_value(self.lua, {
            "raw": _plain(raw), "mods": active,
            "replacement_product_target_families": {"research_batteries": True, "research_sulfur": True},
            "excluded_product_target_recipes": {
                "research_batteries": ["battery"],
                "research_sulfur": ["aromatics-to-lubricant", "sulfur"],
            },
        }))
        rebuilt = {row["name"]: _plain(row)["effects"] for row in rows.values()}
        self.assertEqual([{"type": "change-recipe-productivity", "recipe": "nas-battery", "change": 0.1}],
                         rebuilt["recipe-prod-research_batteries-1"])
        self.assertEqual([{"type": "change-recipe-productivity", "recipe": "extract-sulfur", "change": 0.1}],
                         rebuilt["recipe-prod-research_sulfur-1"])

        malformed = _lua_value(self.lua, {"raw": _plain(raw), "mods": active,
            "replacement_product_target_families": {"research_batteries": "yes"}})
        with self.assertRaisesRegex(Exception, "invalid replacement product target families"):
            self.extension["extend"](rows, values, malformed)

    def test_armor_uses_the_captured_ratio_and_preserves_two_historical_item_pattern_groups(self):
        rows, raw, values, selection = self._modern_rows("armor-bobwarfare")
        armor = next(row for row in rows if row["name"] == "recipe-prod-research_armor_components-1")
        self.assertEqual(0.02, armor["effects"][0]["change"])
        self.assertEqual(5, _plain(values)["streams"]["research_armor_components"]["effect_percent"])
        self.assertEqual({"research_armor_components": True}, _plain(selection["exact_product_target_families"]))
        self.assertEqual({
            "research_armor_components": True,
            "research_bullets": True,
            "research_rockets": True,
        }, _plain(selection["replacement_product_target_families"]))
        raw["recipe"]["unreviewed-armor-plate"] = {
            "enabled": False, "ingredients": [], "results": [{"type": "item", "name": "unreviewed-armor-plate", "amount": 1}],
        }
        raw["item"]["unreviewed-armor-plate"] = {}
        rerun = self.modern["technologies"](selection, values)
        self.extension["extend"](rerun, values, _lua_value(self.lua, {
            "raw": raw, "mods": self.active("armor-bobwarfare"),
            "exact_product_target_families": _plain(selection["exact_product_target_families"]),
            "exact_product_bindings": _plain(selection["exact_product_bindings"]),
            "replacement_product_target_families": _plain(selection["replacement_product_target_families"]),
        }))
        row = next(item for item in _plain(rerun) if item["name"] == armor["name"])
        self.assertEqual(2, len(row["effects"]))
        self.assertEqual("unreviewed-armor-plate", row["effects"][1]["recipe"])
        self.assertEqual(0.02, row["effects"][1]["change"])

        broad = _lua_value(self.lua, [{
            "name": "recipe-prod-research_armor_components-1",
            "effects": [{"type": "change-recipe-productivity", "recipe": "seed", "change": 0.02}],
        }])
        broad_raw = {
            "item": {
                "bob-mech-armor-plate": {},
                "fixture-armor-plating": {},
            },
            "recipe": {
                "bob-mech-armor-plate": {"ingredients": [], "results": [
                    {"type": "item", "name": "bob-mech-armor-plate", "amount": 1}]},
                "fixture-armor-plating": {"ingredients": [], "results": [
                    {"type": "item", "name": "fixture-armor-plating", "amount": 1}]},
            },
        }

        # Opponent: the inherited Base weights (.5/.2) are correct only for
        # its 10% stream.  At Bob Warfare's captured 5%, leaving those broad
        # rules admitted would silently halve both historical groups.
        inherited = _lua_value(self.lua, [{
            "name": "recipe-prod-research_armor_components-1",
            "effects": [{"type": "change-recipe-productivity", "recipe": "seed", "change": 0.02}],
        }])
        self.extension["extend"](inherited, values, _lua_value(self.lua, {
            "raw": broad_raw, "mods": self.active("armor-bobwarfare"),
            "replacement_product_target_families": {"research_armor_components": True},
        }))
        self.assertEqual([
            {"type": "change-recipe-productivity", "recipe": "fixture-armor-plating", "change": 0.025},
            {"type": "change-recipe-productivity", "recipe": "bob-mech-armor-plate", "change": 0.01},
        ], _plain(inherited[1]["effects"]))

        # The exact-family marker has scope only over the incompatible Base
        # rules.  Its separately admitted bindings remain broad patterns in
        # the same collector pass; they are not a one-recipe Bob-mech escape.
        self.extension["extend"](broad, values, _lua_value(self.lua, {
            "raw": broad_raw, "mods": self.active("armor-bobwarfare"),
            "exact_product_target_families": _plain(selection["exact_product_target_families"]),
            "exact_product_bindings": _plain(selection["exact_product_bindings"]),
            "replacement_product_target_families": {"research_armor_components": True},
        }))
        # The collector has an authored replacement priority: plating keeps
        # its historical 5% group ahead of the 2% armor-plate group.
        self.assertEqual([
            {"type": "change-recipe-productivity", "recipe": "fixture-armor-plating", "change": 0.05},
            {"type": "change-recipe-productivity", "recipe": "bob-mech-armor-plate", "change": 0.02},
        ], _plain(broad[1]["effects"]))

    def test_bob_warfare_rebuilds_the_two_captured_effect_vectors_in_published_order(self):
        profile = self.profiles["armor-bobwarfare"]
        captured = profile["published_bob_warfare_effect_vectors"]
        expected = {row["name"]: deepcopy(row["effects"]) for row in captured["rows"]}
        active = self.active("armor-bobwarfare")
        values = self._values(active)
        selection = self.catalogue["select"](_lua_value(self.lua, active))
        selected_replacements = _plain(selection["replacement_product_target_families"])
        self.assertEqual({
            "research_armor_components": True,
            "research_bullets": True,
            "research_rockets": True,
        }, selected_replacements)
        self.assertEqual(10, values["streams"]["research_bullets"]["effect_percent"])
        self.assertEqual(10, values["streams"]["research_rockets"]["effect_percent"])

        rows = self.modern["technologies"](selection, values)
        seeds = {
            row["name"]: _plain(row["effects"])
            for row in rows.values()
            if row["name"] in expected
        }
        self.assertEqual({
            "recipe-prod-research_bullets-1": [
                {"type": "change-recipe-productivity", "recipe": "firearm-magazine", "change": 0.1},
                {"type": "change-recipe-productivity", "recipe": "shotgun-shell", "change": 0.1},
                {"type": "change-recipe-productivity", "recipe": "piercing-rounds-magazine", "change": 0.05},
                {"type": "change-recipe-productivity", "recipe": "piercing-shotgun-shell", "change": 0.05},
                {"type": "change-recipe-productivity", "recipe": "uranium-rounds-magazine", "change": 0.02},
            ],
            "recipe-prod-research_rockets-1": [
                {"type": "change-recipe-productivity", "recipe": "rocket", "change": 0.1},
                {"type": "change-recipe-productivity", "recipe": "explosive-rocket", "change": 0.05},
                {"type": "change-recipe-productivity", "recipe": "atomic-bomb", "change": 0.02},
            ],
        }, seeds)

        raw = {"item": {}, "recipe": {}, "technology": {}, "tool": {}, "lab": {}}
        for effects in expected.values():
            for effect in effects:
                raw["recipe"][effect["recipe"]] = {
                    "enabled": False,
                    "ingredients": [],
                    "results": [{"type": "item", "name": effect["recipe"], "amount": 1}],
                }
        report = _plain(self.extension["extend"](rows, values, _lua_value(self.lua, {
            "raw": raw,
            "mods": active,
            "exact_product_target_families": _plain(selection["exact_product_target_families"]),
            "exact_product_bindings": _plain(selection["exact_product_bindings"]),
            "replacement_product_target_families": selected_replacements,
        })))
        observed = {
            row["name"]: _plain(row["effects"])
            for row in rows.values()
            if row["name"] in expected
        }
        self.assertEqual(expected, observed)
        self.assertEqual(33, report["work"]["recipes"])
        self.assertEqual(33, report["extended_effects"])

    def test_preflight_rejects_named_field_drift_without_world_scans(self):
        armor_raw = self._raw("armor-bobwarfare")
        armor_raw["recipe"]["bob-mech-armor-plate"]["allow_productivity"] = False
        with self.assertRaisesRegex(Exception, "armor route changed"):
            self.armor["preflight"](_lua_value(self.lua, armor_raw))

        coal_raw = self._raw("py-coal")
        coal_raw["technology"]["wood-processing"]["prerequisites"] = []
        values = self._values(self.active("py-coal"))
        with self.assertRaisesRegex(Exception, "wood-processing no longer owns log1"):
            self.py_materials["technologies"](values, _lua_value(self.lua, coal_raw),
                                              _lua_value(self.lua, self.active("py-coal")))

        high_raw = self._raw("py-alienlife-hightech")
        high_raw["recipe"]["bhoddos-culture-mk01"]["allow_productivity"] = False
        with self.assertRaisesRegex(Exception, "breeding route changed"):
            self.py_hightech["preflight"](_lua_value(self.lua, high_raw))
        high_raw = self._raw("py-alienlife-hightech")
        high_raw["recipe"]["arqad-mk02-breeding"]["maximum_productivity"] = 3
        with self.assertRaisesRegex(Exception, "breeding route changed"):
            self.py_hightech["preflight"](_lua_value(self.lua, high_raw))

    def test_armor_item_artwork_is_unowned_and_does_not_change_emitted_research(self):
        baseline, writes, preflights = self._data_final_rows("armor-bobwarfare")
        self.assertEqual((1, 1), (writes, preflights))
        for icon, size, layers in (
            ("__fixture-art__/armor.png", 128, None),
            ("__bobwarfare__/graphics/icons/spidertron/mech-armor-plate.png", 64, None),
            (None, None, [{"icon": "__fixture-art__/armor-layer.png", "icon_size": 64}]),
        ):
            raw = self._raw("armor-bobwarfare")
            item = raw["item"]["bob-mech-armor-plate"]
            item.pop("icon", None)
            item.pop("icon_size", None)
            if icon is not None:
                item["icon"] = icon
            if size is not None:
                item["icon_size"] = size
            if layers is not None:
                item["icons"] = layers
            snapshot = deepcopy(raw)
            emitted, writes, preflights = self._data_final_rows("armor-bobwarfare", raw)
            self.assertEqual(baseline, emitted, "unconsumed item artwork changed MIR's authored research")
            self.assertEqual((1, 1), (writes, preflights))
            self.assertEqual(snapshot, raw)

        missing_item = self._raw("armor-bobwarfare")
        missing_item["item"].pop("bob-mech-armor-plate")
        missing_item["fluid"] = {"bob-mech-armor-plate": {}}
        with self.assertRaisesRegex(Exception, "armor item is unavailable"):
            self._data_final_rows("armor-bobwarfare", missing_item)

        missing_owner = self._raw("armor-bobwarfare")
        missing_owner["technology"].pop("bob-tankotron")
        with self.assertRaisesRegex(Exception, "armor owner changed"):
            self._data_final_rows("armor-bobwarfare", missing_owner)

    def test_profile_absence_is_inactive_and_known_science_variant_is_refused(self):
        selection = self.catalogue["select"](_lua_value(self.lua, {"base": "2.0.77"}))
        names = {definition["key"] for definition in selection["definitions"].values()}
        self.assertNotIn("research_armor_components", names)
        self.assertNotIn("research_material_py_log", names)
        self.assertNotIn("research_breeding", names)
        active = self.active("py-alienlife-hightech")
        active["space-age"] = "2.0.77"
        with self.assertRaisesRegex(Exception, "Py saved-profile transition"):
            self.catalogue["select"](_lua_value(self.lua, active))
        active = self.active("py-alienlife-hightech")
        del active["pyhightech"]
        with self.assertRaisesRegex(Exception, "AlienLife changes the captured Py Coal log route"):
            self.catalogue["select"](_lua_value(self.lua, active))
        incompatible = self.profiles["py-alienlife-hightech"]["excluded_py_coal_log_route"]
        self.assertEqual("log1", incompatible["recipe"])
        self.assertEqual(["moss-mk01"], incompatible["owner"]["prerequisites"])

    def test_settings_keep_identities_and_the_captured_py_sets_are_visible(self):
        for identifier in self.profiles:
            self.lua.globals().mods = _lua_value(self.lua, self.active(identifier))
            settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
            specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
            for family, captured in self.profiles[identifier]["named_settings"].items():
                for expected in captured:
                    row = expected["row"]
                    observed = specs[row["name"]]
                    for field in (
                        "type", "setting_type", "default_value", "minimum_value", "maximum_value",
                        "order", "hidden", "localised_name", "localised_description",
                    ):
                        self.assertEqual(row.get(field), observed.get(field), f"{identifier} {row['name']} {field}")
        self.lua.globals().mods = _lua_value(self.lua, self.active("py-coal"))
        settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
        specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
        self.assertIn("hidden", specs["ips-enable-research_supercapacitor"])
        self.assertNotIn("hidden", specs["ips-enable-research_armor_components"])
        for identifier in ("py-coal", "py-alienlife-hightech"):
            self.lua.globals().mods = _lua_value(self.lua, self.active(identifier))
            settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
            specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
            for family in self.profiles[identifier]["visible_setting_families"]:
                for prefix in (
                    "ips-enable-", "ips-cost-base-", "ips-cost-linear-increment-", "ips-cost-growth-",
                    "ips-max-level-", "ips-research-time-", "ips-effect-per-level-",
                ):
                    self.assertNotIn("hidden", specs[prefix + family], f"{identifier} {prefix}{family}")
        self.lua.globals().mods = _lua_value(self.lua, self.active("py-alienlife-hightech"))
        settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
        specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
        self.assertIn("hidden", specs["ips-enable-research_supercapacitor"])
        self.lua.globals().mods = _lua_value(self.lua, {"base": "2.0.77"})
        settings = self.lua.execute('package.loaded["research.settings"]=nil; return require("research.settings")')
        specs = {spec["name"]: _plain(spec) for spec in settings["prototypes"]().values()}
        self.assertIn("hidden", specs["ips-enable-research_material_py_log"])

    def test_modded_continuations_keep_captured_weights_presentation_and_policy_behavior(self):
        coal_active = self.active("py-coal")
        coal_selection = self.catalogue["select"](_lua_value(self.lua, coal_active))
        coal_rows = {row["id"]: row for row in coal_selection["continuations"].values()}
        coal = self.modern["continuation"](coal_rows["braking-force-8"], self._values(coal_active))
        self.assertEqual("autotech-[000235]-[braking-force-7]", coal["order"])
        self.assertEqual([
            ["utility-science-pack", 1], ["production-science-pack", 2], ["chemical-science-pack", 3],
            ["logistic-science-pack", 6], ["automation-science-pack", 10], ["military-science-pack", 3],
        ], _plain(coal["unit"]["ingredients"]))

        high_active = self.active("py-alienlife-hightech")
        high_selection = self.catalogue["select"](_lua_value(self.lua, high_active))
        high_rows = {row["id"]: row for row in high_selection["continuations"].values()}
        high = self.modern["continuation"](high_rows["research-speed-7"], self._values(high_active))
        self.assertEqual("autotech-[000722]-[research-speed-6]", high["order"])
        self.assertEqual(128, high["icon_size"])
        self.assertEqual("__pycoalprocessinggraphics__/graphics/technology/energy-1.png", high["icons"][1]["icon"])
        self.lua.globals().mods = _lua_value(self.lua, high_active)
        declaration_catalogue = self.lua.execute('package.loaded["research.catalogue"]=nil; return require("research.catalogue")')
        declared = {row["id"]: _plain(row) for row in declaration_catalogue["declared"]().values()}
        self.assertEqual("autotech-[000722]-[research-speed-6]", declared["research-speed-7"]["native_order"])
        self.assertEqual([
            ["utility-science-pack", 1], ["py-science-pack-4", 2], ["production-science-pack", 3],
            ["py-science-pack-3", 6], ["chemical-science-pack", 10], ["py-science-pack-2", 20],
            ["logistic-science-pack", 30], ["py-science-pack-1", 60], ["automation-science-pack", 100],
            ["military-science-pack", 20], ["space-science-pack", 1],
        ], _plain(high["unit"]["ingredients"]))

        # HighTech's shared amount map includes its optional space pack; the
        # non-space vector must emit only its selected names and retain weights.
        non_space = self.catalogue["science_ingredients"](
            "science_py_hightech", high_rows["inserter-capacity-bonus-8"]["science_amounts"]
        )
        self.assertEqual(10, len(non_space))
        self.assertEqual(["military-science-pack", 20], _plain(non_space[10]))
        with self.assertRaisesRegex(Exception, "authored science amount is invalid"):
            self.catalogue["science_ingredients"]("science_py_coal", _lua_value(self.lua, {
                "utility-science-pack": 1.5,
            }))
        invalid_order = _plain(high_rows["research-speed-7"])
        invalid_order["order"] = False
        with self.assertRaisesRegex(Exception, "continuation order is invalid"):
            self.modern["continuation"](_lua_value(self.lua, invalid_order), self._values(high_active))
        invalid_icon_size = _plain(high_rows["research-speed-7"])
        invalid_icon_size["icon_size"] = 0
        with self.assertRaisesRegex(Exception, "continuation icon size is invalid"):
            self.modern["continuation"](_lua_value(self.lua, invalid_icon_size), self._values(high_active))

        def science_raw(include_space=False):
            packs = [
                "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                "production-science-pack", "military-science-pack", "utility-science-pack",
                "py-science-pack-1", "py-science-pack-2", "py-science-pack-3", "py-science-pack-4",
            ]
            if include_space:
                packs.append("space-science-pack")
            raw = {
                "tool": {name: {} for name in packs},
                "technology": {name: {} for name in packs},
                "lab": {"fixture": {"inputs": packs}},
                "recipe": {},
            }
            if include_space:
                raw["technology"]["space-science-pack"] = {
                    "effects": [{"type": "unlock-recipe", "recipe": "space-science-pack"}],
                    "research_trigger": {"type": "build-entity", "entity": "asteroid-collector"},
                    "prerequisites": ["space-platform"],
                }
                raw["technology"]["space-platform"] = {}
                raw["recipe"]["space-science-pack"] = {
                    "enabled": False,
                    "results": [{"type": "item", "name": "space-science-pack", "amount": 1}],
                }
            return raw

        # The normal policy only removes packs when asked and preserves all
        # selected source amounts.  Policy-added space science receives the
        # documented default amount rather than a stale adapter amount.
        reduced = self.modern["continuation"](high_rows["inserter-capacity-bonus-8"], self._values(high_active))
        result = self.science["apply"](reduced, self.lua.table(), self.science["prepare"](_lua_value(self.lua, {
            "raw": science_raw(), "options": {"mir-science-pack-ingredient-policy": "all-official"},
            "target": {"id": "f200"}, "mods": {},
        })))
        self.assertTrue(result["enabled"])
        self.assertEqual([
            ["utility-science-pack", 1], ["production-science-pack", 3], ["chemical-science-pack", 10],
            ["logistic-science-pack", 30], ["automation-science-pack", 100], ["military-science-pack", 20],
        ], _plain(reduced["unit"]["ingredients"]))

        added = self.modern["continuation"](high_rows["inserter-capacity-bonus-8"], self._values(high_active))
        result = self.science["apply"](added, self.lua.table(), self.science["prepare"](_lua_value(self.lua, {
            "raw": science_raw(True), "options": {"mir-science-pack-ingredient-policy": "space"},
            "target": {"id": "f200"}, "mods": {"space-age": "2.0.77"},
        })))
        self.assertTrue(result["enabled"])
        added_ingredients = _plain(added["unit"]["ingredients"])
        self.assertEqual(["space-science-pack", 1], added_ingredients[-1])

        coal["unit"]["ingredients"][1][2] = 999
        again = self.modern["continuation"](
            self.catalogue["select"](_lua_value(self.lua, coal_active))["continuations"][1], self._values(coal_active)
        )
        self.assertEqual(1, again["unit"]["ingredients"][1][2])

    def test_outputs_are_detached_and_py_catalogue_declarations_keep_both_stages(self):
        active = self.active("py-coal")
        values, raw = self._values(active), self._raw("py-coal")
        first = self.py_materials["technologies"](values, _lua_value(self.lua, raw), _lua_value(self.lua, active))
        first[1]["effects"][1]["recipe"] = "corrupted"
        second = _plain(self.py_materials["technologies"](values, _lua_value(self.lua, raw), _lua_value(self.lua, active)))
        self.assertEqual("log1", second[0]["effects"][0]["recipe"])
        self.lua.globals().mods = _lua_value(self.lua, active)
        catalogue = self.lua.execute('package.loaded["research.catalogue"]=nil; return require("research.catalogue")')
        declared = {
            row["id"]: _plain(row)
            for row in catalogue["declared"]().values()
            if row["id"].startswith("recipe-prod-research_material_py_log-")
        }
        self.assertEqual({"recipe-prod-research_material_py_log-1", "recipe-prod-research_material_py_log-4"}, set(declared))
        self.assertEqual(1, declared["recipe-prod-research_material_py_log-1"]["progression"])
        self.assertEqual(4, declared["recipe-prod-research_material_py_log-4"]["progression"])

        for identifier in ("armor-bobwarfare", "py-alienlife-hightech"):
            self.lua.globals().mods = _lua_value(self.lua, self.active(identifier))
            catalogue = self.lua.execute('package.loaded["research.catalogue"]=nil; return require("research.catalogue")')
            declared = {row["id"]: _plain(row) for row in catalogue["declared"]().values()}
            for identifier_row, expected in self._expected_rows(identifier).items():
                self.assertIn(identifier_row, declared)
                self.assertEqual(expected["level"], declared[identifier_row]["progression"])
                self.assertEqual(expected["effects"][0]["recipe"], declared[identifier_row]["recipe"])

        first_selection = self.catalogue["select"](_lua_value(self.lua, self.active("py-alienlife-hightech")))
        first_selection["required_product_targets"]["research_breeding"][1] = "corrupted"
        first_selection["additional_product_bindings"][1]["products"][1]["name"] = "corrupted"
        second_selection = _plain(self.catalogue["select"](_lua_value(self.lua, self.active("py-alienlife-hightech"))))
        self.assertEqual("arqad-mk02-breeding", second_selection["required_product_targets"]["research_breeding"][0])
        self.assertEqual("supercapacitor", second_selection["additional_product_bindings"][0]["products"][0]["name"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ArmorPyCatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
