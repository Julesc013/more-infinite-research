"""Hash-locked F200 Krastorio 2 Base catalogue admission; no native result claimed."""
import argparse
import hashlib
import json
from pathlib import Path
from historical_sources import read_published_source
import sys
import unittest

from native_credit_oracle import (
    native_credit_carrier_rows,
    split_public_and_native_credit_rows,
)


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/k2-base-f200-captured-facts.json"
sys.path.insert(0, str(ROOT / "tools"))
import compare_k2_base


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


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


class K2BaseCatalogueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        profile = ROOT / cls.facts["profile"]
        if _sha256(profile) != cls.facts["profile_sha256"]:
            raise AssertionError(f"hash-locked K2 Base input changed: {profile}")
        # The complete dump is retained as developer custody rather than a
        # hosted-test dependency. When it is locally present, still prove it
        # is the exact source of the committed portable native subset.
        cls.raw_path = ROOT / cls.facts["raw"]["path"]
        native_settings = ROOT / cls.facts["native_settings"]["path"]
        if native_settings.is_file() and _sha256(native_settings) != cls.facts["native_settings"]["sha256"]:
            raise AssertionError("captured native settings changed")
        if cls.raw_path.is_file():
            if _sha256(cls.raw_path) != cls.facts["raw"]["sha256"]:
                raise AssertionError(f"hash-locked K2 Base raw changed: {cls.raw_path}")
            cls._verify_local_raw_subset(json.loads(cls.raw_path.read_text(encoding="utf-8")))
        if cls.facts["captured_native_subset"]["source_sha256"] != cls.facts["raw"]["sha256"]:
            raise AssertionError("captured native subset has the wrong raw provenance")
        for source in (cls.facts["authored_selector_evidence"], cls.facts["direct_effect_evidence"]):
            read_published_source(ROOT, source["path"], source["sha256"])
        for name in ("base", "direct"):
            source = cls.facts["catalogue_evidence"]
            if _sha256(ROOT / source[f"{name}_path"]) != source[f"{name}_sha256"]:
                raise AssertionError(f"catalogue evidence changed: {source[f'{name}_path']}")

    @staticmethod
    def _recipe_products(recipe):
        if isinstance(recipe.get("results"), list):
            values = recipe["results"]
        elif isinstance(recipe.get("result"), str):
            values = [{"type": "item", "name": recipe["result"],
                       "amount": recipe.get("result_count", 1)}]
        else:
            values = []
        rows = []
        for row in values:
            if isinstance(row, list):
                rows.append(("item", row[0], row[1] if len(row) > 1 else 1))
            else:
                rows.append((row.get("type", "item"), row.get("name"), row.get("amount", 1)))
        return rows

    @staticmethod
    def _field_at(value, path):
        for field in path:
            if isinstance(field, int):
                value = value[field] if isinstance(value, list) and 0 <= field < len(value) else None
            else:
                value = value.get(field) if isinstance(value, dict) else None
        return value

    @classmethod
    def _verify_local_raw_subset(cls, raw):
        subset = cls.facts["captured_native_subset"]
        for name in subset["native_recipe_names"]:
            if not isinstance(raw.get("recipe", {}).get(name), dict):
                raise AssertionError(f"captured named recipe is missing: {name}")
        for name in subset["native_technology_names"]:
            if not isinstance(raw.get("technology", {}).get(name), dict):
                raise AssertionError(f"captured named technology is missing: {name}")
        selected_recipes = subset["recipe_product_fields"]
        if len({row["recipe"] for row in selected_recipes}) != len(selected_recipes):
            raise AssertionError("captured K2 recipe product facts must be unique")
        for selected in selected_recipes:
            recipe = raw.get("recipe", {}).get(selected["recipe"])
            if not isinstance(recipe, dict):
                raise AssertionError(f"captured recipe missing from local raw: {selected['recipe']}")
            product = (selected.get("type", "item"), selected["product"], selected["amount"])
            if product not in cls._recipe_products(recipe):
                raise AssertionError(f"captured product field drifted: {selected['recipe']}")
        for selected in subset["item_place_results"]:
            item = raw.get("item", {}).get(selected["name"])
            entity = raw.get(selected["entity_type"], {}).get(selected["place_result"])
            if not isinstance(item, dict) or item.get("place_result") != selected["place_result"] or not isinstance(entity, dict):
                raise AssertionError(f"captured item/place-result field drifted: {selected['name']}")
        for selected in subset["item_names"]:
            if not isinstance(raw.get(selected["type"], {}).get(selected["name"]), dict):
                raise AssertionError(f"captured item is missing: {selected['name']}")
        for category in cls.facts["k2_base_native_category_sources"]:
            value = raw.get(category["prototype_type"], {}).get(category["name"])
            if not isinstance(value, dict):
                raise AssertionError(f"captured category source is missing: {category['name']}")
            for field in category["field_path"]:
                value = value.get(field) if isinstance(value, dict) else None
            if value != category["value"]:
                raise AssertionError(f"captured K2 category drifted: {category['name']}")
        for presentation in cls.facts["presentation_icon_facts"]:
            native = presentation["native"]
            prototype = raw.get(native["prototype_type"], {}).get(native["name"])
            if not isinstance(prototype, dict):
                raise AssertionError(f"captured icon source is missing: {native['name']}")
            if cls._field_at(prototype, native["icon_path"]) != native["icon"]:
                raise AssertionError(f"captured K2 icon drifted: {presentation['id']}")
            if cls._field_at(prototype, native["icon_size_path"]) != native["icon_size"]:
                raise AssertionError(f"captured K2 icon size drifted: {presentation['id']}")
        gear = subset["gear"]
        item = raw.get("item", {}).get(gear["native_item"])
        if not isinstance(item, dict) or item.get("icon") != gear["native_item_icon"]:
            raise AssertionError("captured K2 Base gear icon drifted")
        for name in cls.facts["standard_science"]:
            if not isinstance(raw.get("tool", {}).get(name), dict):
                raise AssertionError(f"captured standard science is missing: {name}")
        lab = raw.get("lab", {}).get(cls.facts["advanced_lab"]["name"])
        if not isinstance(lab, dict) or lab.get("inputs") != cls.facts["advanced_lab"]["inputs"]:
            raise AssertionError("captured K2 advanced-lab inputs drifted")
        for continuation in cls.facts["continuations"]:
            for key in ("predecessor", "previous"):
                expected = continuation[key]
                technology = raw.get("technology", {}).get(expected["name"])
                unit = technology.get("unit", {}) if isinstance(technology, dict) else {}
                if unit.get("count") != expected["count"] or unit.get("time") != expected["time"]:
                    raise AssertionError(f"captured continuation cost/time drifted: {expected['name']}")
            predecessor = continuation["predecessor"]
            technology = raw["technology"][predecessor["name"]]
            if technology.get("effects") != predecessor["effects"]:
                raise AssertionError(f"captured continuation effects drifted: {predecessor['name']}")

    @classmethod
    def _captured_raw_subset(cls):
        subset = cls.facts["captured_native_subset"]
        raw = {
            "technology": {name: {} for name in subset["native_technology_names"]},
            "recipe": {name: {} for name in subset["native_recipe_names"]},
            "tool": {name: {} for name in cls.facts["standard_science"]},
            "lab": {cls.facts["advanced_lab"]["name"]: {"inputs": cls.facts["advanced_lab"]["inputs"]}},
            "item": {},
            "module": {},
        }
        for row in subset["recipe_product_fields"]:
            raw["recipe"][row["recipe"]] = {
                "results": [{"type": "item", "name": row["product"], "amount": row["amount"]}]
            }
        for row in subset["item_place_results"]:
            raw["item"][row["name"]] = {"place_result": row["place_result"]}
            raw.setdefault(row["entity_type"], {})[row["place_result"]] = {}
        for row in subset["item_names"]:
            raw.setdefault(row["type"], {})[row["name"]] = {}
        for continuation in cls.facts["continuations"]:
            predecessor = continuation["predecessor"]
            raw["technology"][predecessor["name"]] = {
                "unit": {"count": predecessor["count"], "time": predecessor["time"]},
                "effects": predecessor["effects"],
            }
            previous = continuation["previous"]
            raw["technology"][previous["name"]] = {
                "unit": {"count": previous["count"], "time": previous["time"]},
            }
        return raw

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
        ''')

    def _run_captured_subset_data_stage(self, startup=None):
        profile = json.loads((ROOT / self.facts["profile"]).read_text(encoding="utf-8"))
        self.assertEqual(profile["target"], "f200")
        self.assertEqual(profile["engine"]["version"], self.facts["engine"]["version"])
        mods = {entry["name"]: entry["version"] for entry in profile["mods"] if entry["enabled"]}
        self.assertIn("Krastorio2", mods)
        self.assertIn("Krastorio2Assets", mods)
        self.assertNotIn("space-age", mods)

        self.lua.globals().captured_raw = _lua_value(self.lua, self._captured_raw_subset())
        self.lua.globals().captured_mods = _lua_value(self.lua, mods)
        self.lua.globals().captured_startup = _lua_value(self.lua, startup or {})
        self.lua.execute(r'''
          f200()
          mods = captured_mods
          settings = {startup = captured_startup}
          helpers = {}
          log = function() end
          emitted = {}
          data = {raw = captured_raw}
          function data:extend(rows)
            for _, row in ipairs(rows) do
              assert(type(self.raw[row.type]) == "table", "unknown output type " .. tostring(row.type))
              assert(self.raw[row.type][row.name] == nil, "duplicate data:extend output " .. row.name)
              self.raw[row.type][row.name] = row
              emitted[#emitted + 1] = row.name
            end
          end
          assert(loadfile(player_root .. "/data-final-fixes.lua"))()
        ''')

    def test_f200_k2_base_emits_the_hash_locked_catalogue_once(self):
        self._run_captured_subset_data_stage()
        # Whole independent published rows: this catches omitted fields, tuning,
        # presentation, progression and targets beyond the mechanism assertions.
        expected = compare_k2_base.intended_output()
        rows = {row["name"]: row["row"] for row in expected["data"]["additions"]
                if row["type"] == "technology"}
        actual = self.lua.globals().data.raw.technology
        emitted_names = [str(name) for name in self.lua.globals().emitted.values()]
        self.assertEqual(len(emitted_names), len(set(emitted_names)), "duplicate K2 Base output")
        emitted_rows = {name: _plain(actual[name]) for name in emitted_names}
        actual_public, actual_credit = split_public_and_native_credit_rows(emitted_rows)
        expected_credit = native_credit_carrier_rows(
            rows, set(self._captured_raw_subset()["recipe"])
        )
        self.assertEqual(actual_public, rows)
        self.assertEqual(actual_credit, expected_credit)
        self.assertEqual(set(emitted_rows), set(rows) | set(expected_credit))
        for name, wanted in rows.items():
            found = _plain(actual[name])
            self.assertTrue(compare_k2_base.catalogue._same(found, wanted),
                            f"{name}: {compare_k2_base.catalogue._changed_paths(wanted, found)}")
        # Opponents exercise the whole-row boundary, including numeric types.
        from copy import deepcopy
        for name, field, changed in (
                ("recipe-prod-research_gears-1", "effects", []),
                ("recipe-prod-research_copper-1", "max_level", 1),
                ("braking-force-8", "hidden", 0)):
            mutated = deepcopy(rows[name])
            mutated[field] = changed
            self.assertFalse(compare_k2_base.catalogue._same(rows[name], mutated))
        self.lua.globals().facts = _lua_value(self.lua, self.facts)
        self.lua.globals().expected_ids = _lua_value(self.lua, self.facts["emitted_ids"])
        self.lua.execute(r'''
          local catalogue = require("compatibility.modern_catalogue")
          local runtime_catalogue = require("research.catalogue")
          local raw = data.raw
          local expected, emitted_by_name = {}, {}
          for _, id in ipairs(expected_ids) do expected[id] = true end
          assert(#expected_ids == 54)
          for _, id in ipairs(emitted) do
            assert(not emitted_by_name[id], "duplicate output " .. id)
            emitted_by_name[id] = true
          end
          for id in pairs(expected) do assert(emitted_by_name[id], "missing expected output " .. id) end

          local selection = catalogue.select(mods)
          assert(selection.profile == "k2-base-f200" and #selection.definitions == 47
            and #selection.continuations == 6 and #selection.native_owners == 0
            and selection.k2_imersite == false)
          local selected_continuations = {}
          for _, continuation in ipairs(selection.continuations) do selected_continuations[continuation.id] = continuation end

          -- Each emitted named reference is tied to the captured native raw;
          -- the test does not use generated output as its oracle.
          local standard, cards, lab_inputs = {}, {}, {}
          for _, name in ipairs(facts.standard_science) do standard[name] = true end
          for _, name in ipairs(facts.not_admitted.science_cards) do cards[name] = true end
          for _, name in ipairs(raw.lab[facts.advanced_lab.name].inputs) do lab_inputs[name] = true end
          for _, name in ipairs(facts.standard_science) do
            assert(raw.tool[name] and raw.technology[name] and lab_inputs[name], "missing standard science/lab fact " .. name)
          end
          for _, technology_name in ipairs(expected_ids) do
            local technology, recipes = raw.technology[technology_name], {}
            assert(technology and technology.enabled ~= false, "default K2 Base output disabled " .. technology_name)
            for _, ingredient in ipairs(technology.unit.ingredients) do
              assert(standard[ingredient[1]] and not cards[ingredient[1]],
                "K2 Base must retain unreduced standard science for " .. technology_name)
              assert(lab_inputs[ingredient[1]], "K2 advanced lab cannot accept " .. ingredient[1])
            end
            for _, prerequisite in ipairs(technology.prerequisites) do
              assert(raw.technology[prerequisite], "missing named prerequisite " .. prerequisite)
            end
            for _, effect in ipairs(technology.effects) do
              if effect.type == "change-recipe-productivity" then
                assert(raw.recipe[effect.recipe], "missing named recipe " .. effect.recipe)
                assert(not recipes[effect.recipe], "duplicate productivity target " .. technology_name .. ":" .. effect.recipe)
                recipes[effect.recipe] = true
              end
            end
            assert(not technology_name:find("imersite", 1, true) and not technology_name:find("material", 1, true))
          end

           local function same_value(left, right)
             if type(left) ~= type(right) then return false end
             if type(left) ~= "table" then return left == right end
             for key, value in pairs(left) do if not same_value(value, right[key]) then return false end end
             for key in pairs(right) do if left[key] == nil then return false end end
             return true
           end
           local function without_fields(value, omitted)
             local out = {}
             for key, nested in pairs(value) do if not omitted[key] then out[key] = nested end end
             return out
           end
           local base_selection, base_by_key = catalogue.select({base="2.0.77"}), {}
           for _, definition in ipairs(base_selection.definitions) do base_by_key[definition.key] = definition end
           assert(#base_selection.definitions == #selection.definitions)
           for _, definition in ipairs(selection.definitions) do
             local base_definition = base_by_key[definition.key]
             assert(base_definition and same_value(without_fields(definition, {icon=true, icon_size=true}),
               without_fields(base_definition, {icon=true, icon_size=true})),
               "K2 Base changed a non-presentation definition field for " .. definition.key)
           end
           local base_continuations, base_continuations_by_key = catalogue.continuations({base="2.0.77"}), {}
           for _, continuation in ipairs(base_continuations) do base_continuations_by_key[continuation.key] = continuation end
           for _, continuation in ipairs(selection.continuations) do
             local base_continuation = base_continuations_by_key[continuation.key]
             assert(base_continuation and same_value(without_fields(continuation, {effects=true}),
               without_fields(base_continuation, {effects=true})),
               "K2 Base changed a non-effect continuation field for " .. continuation.key)
           end

          local expected_science = {}
          for _, definition in ipairs(selection.definitions) do
            expected_science["recipe-prod-" .. definition.key .. "-1"] = catalogue.science_names(definition.science)
          end
          expected_science["recipe-prod-research_gears-1"] = {
            "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"
          }
          for _, continuation in ipairs(selection.continuations) do
            expected_science[continuation.id] = catalogue.science_names(continuation.science)
          end
          for technology_name, names in pairs(expected_science) do
            local ingredients = raw.technology[technology_name].unit.ingredients
            assert(#ingredients == #names, "science was reduced or extended for " .. technology_name)
            for index, name in ipairs(names) do assert(ingredients[index][1] == name and ingredients[index][2] == 1) end
          end
          local function exact_effects(actual, expected, label)
            assert(#actual == #expected, "effect count drifted for " .. label)
            for index, wanted in ipairs(expected) do
              local found = actual[index]
              for key, value in pairs(wanted) do
                assert(found[key] == value, "effect field drifted for " .. label .. ":" .. key)
              end
              for key, value in pairs(found) do
                assert(wanted[key] == value, "unexpected effect field for " .. label .. ":" .. key)
              end
            end
          end
           local definitions_by_key = {}
           for _, definition in ipairs(selection.definitions) do definitions_by_key[definition.key] = definition end
           assert(#facts.presentation_icon_facts == 10)
           for _, fact in ipairs(facts.presentation_icon_facts) do
             local actual = raw.technology[fact.id].icons[1]
             for key, value in pairs(fact.emitted) do
               assert(actual[key] == value, "presentation field drifted for " .. fact.id .. ":" .. key)
             end
             for key in pairs(actual) do
               assert(fact.emitted[key] == actual[key], "unexpected presentation field for " .. fact.id .. ":" .. key)
             end
             if fact.definition_key then
               local definition = definitions_by_key[fact.definition_key]
               assert(definition and definition.icon == fact.emitted.icon and definition.icon_size == fact.emitted.icon_size,
                 "K2 Base definition icon drifted for " .. fact.definition_key)
             end
           end
           local direct_keys, direct_names = {}, {}
           for _, fact in ipairs(facts.direct_effect_families) do
             local key = fact.id:match("^recipe%-prod%-(.+)%-1$")
             assert(key and not direct_keys[key] and not direct_names[fact.id], "duplicate direct family fact " .. fact.id)
             direct_keys[key], direct_names[fact.id] = true, true
             exact_effects(raw.technology[fact.id].effects, fact.effects, fact.id)
           end
           assert(package.loaded["compatibility.modern_catalogue.k2so"] == nil,
             "K2 Base selection must not import the K2SO body")
           local k2so = require("compatibility.modern_catalogue.k2so")
           local unexpected_k2so_effects = {}
           for key, changed in pairs(k2so.definition_overrides) do
             if direct_keys[key] and changed.effects ~= nil then
               unexpected_k2so_effects[#unexpected_k2so_effects + 1] = key
             end
           end
           assert(#facts.k2so_direct_effect_overrides == 0 and #unexpected_k2so_effects == 0,
             "K2SO must not supply a K2 Base direct-effect override")
          for _, fact in ipairs(facts.continuations) do
            local continuation = raw.technology[fact.id]
            local predecessor_fact = fact.predecessor
            local selected = selected_continuations[fact.id]
            assert(selected and selected.inheritance.last_count == fact.inheritance.last_count
              and selected.inheritance.previous_count == fact.inheritance.previous_count
              and selected.inheritance.research_time == fact.inheritance.research_time,
              "F200 continuation inheritance drifted for " .. fact.id)
            local predecessor = false
            for _, prerequisite in ipairs(continuation.prerequisites) do
              if prerequisite == predecessor_fact.name then predecessor = true end
            end
            assert(raw.technology[predecessor_fact.name] and predecessor,
              "missing captured continuation predecessor " .. fact.id)
            assert(continuation.unit.count_formula == fact.default.count_formula
              and continuation.unit.time == fact.default.time, "F200 inherited cost/time drifted for " .. fact.id)
            assert(#continuation.unit.ingredients == #fact.default.science, "F200 science vector drifted for " .. fact.id)
            for index, name in ipairs(fact.default.science) do
              local ingredient = continuation.unit.ingredients[index]
              assert(ingredient[1] == name and ingredient[2] == 1, "F200 science vector drifted for " .. fact.id)
            end
            exact_effects(continuation.effects, fact.default.effects, fact.id)
          end

          local by_key, percent = {}, {research_gears = 10}
          for _, definition in ipairs(selection.definitions) do
            by_key[definition.key] = definition.family
            if definition.kind == "productivity" then
              percent[definition.family] = definition.tuning and definition.tuning.effect_percent or 10
            end
          end
          local expected_k2, actual_k2 = {}, {}
          for _, fact in ipairs(facts.k2_product_target_additions) do
            expected_k2[fact.family .. ":" .. fact.recipe] = fact.weight
          end
          for _, technology_name in ipairs(expected_ids) do
            local family = technology_name == "recipe-prod-research_gears-1" and "research_gears"
              or by_key[technology_name:match("^recipe%-prod%-(.+)%-1$")]
            if family then
              for _, effect in ipairs(raw.technology[technology_name].effects) do
                if effect.type == "change-recipe-productivity" and effect.recipe:match("^kr%-") then
                  actual_k2[family .. ":" .. effect.recipe] = effect.change / (percent[family] / 100)
                end
              end
            end
          end
          for key, weight in pairs(expected_k2) do
            assert(actual_k2[key] and math.abs(actual_k2[key] - weight) < 1e-12, "missing K2 target " .. key)
          end
          for key in pairs(actual_k2) do assert(expected_k2[key] ~= nil, "unapproved K2 target " .. key) end
          assert(actual_k2["research_modules:kr-speed-module"] == nil)

          for _, owner in ipairs(facts.not_admitted.native_owner_families) do
            assert(raw.technology[owner] == nil, "unadmitted native owner " .. owner)
          end
          local declared, declared_names = runtime_catalogue.declared(), {}
          assert(#declared == 54)
          for _, row in ipairs(declared) do declared_names[row.id] = (declared_names[row.id] or 0) + 1 end
          for id in pairs(expected) do assert(declared_names[id] == 1, "runtime catalogue mismatch " .. id) end

          -- Selection and runtime declaration outputs are detached boundaries.
          selection.definitions[1].effects[1].recipe = "corrupted-test-value"
          assert(catalogue.select(mods).definitions[1].effects[1].recipe ~= "corrupted-test-value")
          declared[1].settings[1] = "corrupted-test-value"
          assert(runtime_catalogue.declared()[1].settings[1] ~= "corrupted-test-value")
        ''')

    def test_k2_base_effect_only_continuations_scale_with_nondefault_settings(self):
        configured = self.facts["continuation_nondefault_settings"]
        startup = {name: {"value": value} for name, value in configured["startup"].items()}
        self._run_captured_subset_data_stage(startup)
        self.lua.globals().facts = _lua_value(self.lua, self.facts)
        self.lua.execute(r'''
          local expected = facts.continuation_nondefault_settings.effects
          for technology_name, effects in pairs(expected) do
            local actual = data.raw.technology[technology_name].effects
            assert(#actual == #effects, "nondefault effect count drifted for " .. technology_name)
            for index, wanted in ipairs(effects) do
              local found = actual[index]
              for key, value in pairs(wanted) do
                assert(found[key] == value, "nondefault effect field drifted for " .. technology_name .. ":" .. key)
              end
              for key, value in pairs(found) do
                assert(wanted[key] == value, "unexpected nondefault field for " .. technology_name .. ":" .. key)
              end
            end
          end
        ''')

    def test_k2_base_binding_is_narrow_and_other_k2_tuples_stay_refused(self):
        self.lua.globals().facts = _lua_value(self.lua, self.facts)
        self.lua.execute(r'''
          local catalogue = require("compatibility.modern_catalogue")
          local gears = require("compatibility.gear_bindings")
          local raw = {recipe = {["iron-gear-wheel"] = {}}}
          local base = {Krastorio2="2.0.19", Krastorio2Assets="2.0.5"}
          local gear_fact = facts.captured_native_subset.gear
          f200()
          assert(catalogue.is_k2_base(base) and not catalogue.is_k2so(base))
          local binding = gears.select(base, raw)
          assert(binding.profile == "k2-base-f200" and binding.recipes[1] == gear_fact.recipe
            and gear_fact.native_item == gear_fact.recipe and binding.icon == gear_fact.native_item_icon)

          local partials = {
            {Krastorio2="2.0.19", Krastorio2Assets="2.0.5", ["Krastorio2-spaced-out"]="2.0.19"},
            {Krastorio2="2.0.19", Krastorio2Assets="2.0.5", ["k2so-assets"]="1.0.0"},
          }
          for _, partial in ipairs(partials) do
            assert(not catalogue.is_k2_base(partial) and not catalogue.is_k2so(partial))
            local partial_ok, partial_message = pcall(gears.select, partial, raw)
            assert(not partial_ok and tostring(partial_message):find("unsupported partial K2SO selection", 1, true))
            mods = partial
            package.loaded["research.catalogue"] = nil
            assert(#require("research.catalogue").declared() == 1,
              "partial F200 K2SO marker must not admit modern rows")
          end
          local missing_assets = {Krastorio2="2.0.19"}
          assert(not catalogue.is_k2_base(missing_assets))

          f210()
          assert(not catalogue.is_k2_base(base))
          local ok, message = pcall(gears.select, base, raw)
          assert(not ok and tostring(message):find("unsupported partial K2SO selection", 1, true))
          mods = base
          package.loaded["research.catalogue"] = nil
          assert(#require("research.catalogue").declared() == 1, "F210 K2 Base must not admit modern rows")

          f200()
          local standalone = {["Krastorio2-spaced-out"]="2.0.19", Krastorio2Assets="2.0.5", ["k2so-assets"]="1.0.0"}
          assert(not catalogue.is_k2_base(standalone) and not catalogue.is_k2so(standalone))
          ok, message = pcall(gears.select, standalone, raw)
          assert(not ok and tostring(message):find("unsupported partial K2SO selection", 1, true))
          mods = standalone
          package.loaded["research.catalogue"] = nil
          assert(#require("research.catalogue").declared() == 1, "standalone F200 K2SO must remain unadmitted")
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(K2BaseCatalogueTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
