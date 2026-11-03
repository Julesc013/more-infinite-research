"""Published SIF hidden paid identities; host controls, never native evidence."""
import argparse
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = json.loads((ROOT / "tests/fixtures/sif-retained-manufacturing/expectations.json").read_bytes())


class SIFRetainedManufacturingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.cargo_research, target.productivity_ignores_stats = false, true
          target.recipe_probability, target.receiver_limits = "probability", false
          mods = {base="2.0.77", ["space-age"]="2.0.77", ["space-is-fake"]="1.0.60",
            ["cr-commons"]="1.0.27"}
          catalogue = require("compatibility.modern_catalogue")
          modern = require("research.modern")
          values = require("research.settings").resolve({})
          function build(raw)
            local selection = catalogue.select(mods, raw)
            local patches = modern.preflight_native_owner_patches(selection, raw, values)
            return modern.technologies(selection, values), selection, patches
          end
          function clone(value)
            if type(value) ~= "table" then return value end
            local out = {}
            for key, item in pairs(value) do out[key] = clone(item) end
            return out
          end
          function same(left, right)
            if type(left) ~= type(right) then return false end
            if type(left) ~= "table" then return left == right or
              (type(left) == "number" and left ~= left and right ~= right) end
            for key, item in pairs(left) do if not same(item, right[key]) then return false end end
            for key in pairs(right) do if left[key] == nil then return false end end
            return true
          end
        ''')
        self.lua.globals().expectations = self.table(EXPECTED["rows"])
        self.raw = self.raw_inputs()
        self.lua.globals().raw = self.table(self.raw)

    def table(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key: self.table(item) for key, item in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.table(item) for item in value])
        return value

    def test_native_target_composition_preserves_every_hidden_paid_vector(self):
        self.lua.execute('''
          local before_raw=clone(raw)
          local rows,selection,patches=build(raw)
          local before_rows=clone(rows)
          local targets=modern.native_owner_product_targets(selection,raw,values,patches,mods)
          require("research.product_target_extension").extend(rows,values,{
            raw=raw,mods=mods,native_owner_targets=targets,
            exact_product_target_families=selection.exact_product_target_families})
          for index,row in ipairs(rows) do
            if row.hidden==true then
              assert(same(row,before_rows[index]),"native collection changed a paid hidden holder")
            end
          end
          assert(same(raw,before_raw),"composition changed upstream input before publication")
        ''')

    def test_hidden_holders_do_not_withhold_legitimate_uncovered_native_recipe(self):
        self.lua.execute('''
          raw.recipe["independent-processing"]={type="recipe",name="independent-processing",
            category="crafting",enabled=false,allow_productivity=true,
            ingredients={{type="item",name="plastic-bar",amount=1}},
            results={{type="item",name="processing-unit",amount=1}}}
          local before_raw=clone(raw)
          local rows,selection,patches=build(raw)
          local before_rows=clone(rows)
          local targets=modern.native_owner_product_targets(selection,raw,values,patches,mods)
          require("research.product_target_extension").extend(rows,values,{
            raw=raw,mods=mods,native_owner_targets=targets,
            exact_product_target_families=selection.exact_product_target_families})
          modern.preflight_collected_native_owner_targets(targets,patches)
          local matched=0
          for _,patch in ipairs(patches) do
            if patch.owner.name=="processing-unit-productivity" then
              for _,effect in ipairs(patch.effects) do
                if effect.type=="change-recipe-productivity" and effect.recipe=="independent-processing" then
                  assert(effect.change==.1,"native adoption did not inherit the original change")
                  matched=matched+1
                end
              end
            end
          end
          assert(matched==1,"valid uncovered producer was not adopted exactly once")
          for index,row in ipairs(rows) do
            if row.hidden==true then
              assert(same(row,before_rows[index]),"uncovered producer changed a paid hidden holder")
            end
          end
          assert(same(raw,before_raw),"detached native adoption changed upstream input")
        ''')

    @staticmethod
    def raw_inputs():
        recipes, owners = {}, {}
        for row in EXPECTED["rows"]:
            for name, owner_id in row["recipes"].items():
                recipe = recipes.setdefault(name, {"type": "recipe", "name": name, "results": []})
                result = {"type": "item", "name": row["product"], "amount": 1}
                if result not in recipe["results"]:
                    recipe["results"].append(result)
                owner = owners.setdefault(owner_id, {
                    "type": "technology", "name": owner_id, "max_level": "infinite",
                    "unit": {"count_formula": "1.5^L*1000", "time": 60, "ingredients": []},
                    "effects": [], "foreign_field": {"keep": True},
                })
                effect = {"type": "change-recipe-productivity", "recipe": name, "change": .1}
                if effect not in owner["effects"]:
                    owner["effects"].append(effect)
        # The old source's important negative: this recipe produces processing
        # units too, but its paid processing-unit identity must not gain it.
        recipes["scrap-recycling"]["results"].append({"type": "item", "name": "processing-unit", "amount": 1})
        return {"recipe": recipes, "technology": owners, "item": {
            row["product"]: {"type": "item", "name": row["product"]} for row in EXPECTED["rows"]
        }}

    def test_exact_published_paid_rows_are_hidden_and_keep_only_their_eleven_effects(self):
        self.lua.execute('''
          local before = clone(raw)
          local rows, selection, patches = build(raw)
          assert(same(raw, before), "retention preflight changed foreign prototypes")
          local by_id = {}
          for _, row in ipairs(rows) do by_id[row.name] = row end
          for _, expected in ipairs(expectations) do
            local row = assert(by_id[expected.id], "missing paid SIF identity " .. expected.id)
            assert(row.hidden == true and row.enabled ~= false and row.level == 1
              and row.max_level == "infinite", "paid identity gained a new visible/disabled/finite route")
            local count, seen = 0, {}
            for _, effect in ipairs(row.effects) do
              assert(effect.type == "change-recipe-productivity" and expected.recipes[effect.recipe]
                and not seen[effect.recipe] and math.abs(effect.change-.1) < 1e-12,
                "paid effect differs from published contract")
              seen[effect.recipe], count = true, count + 1
            end
            local expected_count = 0
            for recipe in pairs(expected.recipes) do
              expected_count = expected_count + 1
              assert(seen[recipe], "lost paid recipe " .. recipe)
            end
            assert(count == expected_count)
          end
          assert(#patches == 0, "default retention mutated a native owner")
          -- Existing public research/cap admission must still select native
          -- owners, not grant cap ownership over the hidden historical rows.
          local declared = require("research.catalogue").declared()
          for _, row in ipairs(declared) do
            for _, expected in ipairs(expectations) do
              assert(row.id ~= expected.id, "hidden paid holder became a public cap/Library row")
            end
          end
        ''')

    def test_wrong_contexts_do_not_import_or_add_the_retention_body(self):
        cases = [
            ("f200", "2.0.77", "2.0.77", "1.0.61"),
            ("f200", "2.0.77", None, "1.0.60"),
            ("f200", "2.0.77", "2.0.77", None),
            ("f200", "2.1.23", "2.1.23", "1.0.60"),
            ("f200", "2.0.77", "2.1.23", "1.0.60"),
            ("f210", "2.1.23", "2.1.23", "1.0.78"),
            ("f210", "2.0.77", "2.0.77", "1.0.60"),
        ]
        for target_id, base, space_age, sif in cases:
            with self.subTest(target=target_id, base=base, space_age=space_age, sif=sif):
                self.lua.globals().target["id"] = target_id
                self.lua.globals().mods["base"] = base
                self.lua.globals().mods["space-age"] = space_age
                self.lua.globals().mods["space-is-fake"] = sif
                self.lua.execute('''
                  package.loaded["compatibility.modern_catalogue.sif_retained"] = nil
                  local selected = catalogue.select(mods)
                  assert(selected.sif_retained == nil and
                    package.loaded["compatibility.modern_catalogue.sif_retained"] == nil,
                    "inactive SIF retention body loaded")
                ''')

    def test_wrong_owner_or_incomplete_coverage_refuses_before_mutation(self):
        for label in ["missing-owner", "wrong-owner-name", "wrong-effect-type", "duplicate-effect",
                      "disabled-owner", "hidden-owner", "finite-owner", "zero-change", "nonfinite-change",
                      "missing-recipe", "wrong-product", "zero-product", "zero-probability",
                      "malformed-result", "malformed-owner-effect"]:
            with self.subTest(label=label):
                raw = copy.deepcopy(self.raw)
                owner = raw["technology"]["plastic-bar-productivity"]
                if label == "missing-owner":
                    del raw["technology"]["plastic-bar-productivity"]
                elif label == "wrong-owner-name":
                    owner["name"] = "foreign-owner"
                elif label == "wrong-effect-type":
                    owner["effects"][0]["type"] = "laboratory-speed"
                elif label == "duplicate-effect":
                    owner["effects"].append(copy.deepcopy(owner["effects"][0]))
                elif label == "disabled-owner":
                    owner["enabled"] = False
                elif label == "hidden-owner":
                    owner["hidden"] = True
                elif label == "finite-owner":
                    owner["max_level"] = 10
                elif label == "zero-change":
                    owner["effects"][0]["change"] = 0
                elif label == "nonfinite-change":
                    owner["effects"][0]["change"] = float("nan")
                elif label == "missing-recipe":
                    del raw["recipe"]["bioplastic"]
                elif label == "wrong-product":
                    raw["recipe"]["bioplastic"]["results"][0]["name"] = "unrelated-item"
                elif label == "zero-product":
                    raw["recipe"]["bioplastic"]["results"][0]["amount"] = 0
                elif label == "zero-probability":
                    raw["recipe"]["bioplastic"]["results"][0]["probability"] = 0
                elif label == "malformed-result":
                    raw["recipe"]["bioplastic"]["results"] = [42]
                else:
                    owner["effects"] = [42]
                self.lua.globals().opponent_raw = self.table(raw)
                self.lua.execute('''
                  local before = clone(opponent_raw)
                  local ok, message = pcall(build, opponent_raw)
                  assert(not ok and string.find(message, "MIR SIF retained", 1, true),
                    "malformed paid-owner coverage admitted or failed outside its boundary")
                  assert(same(opponent_raw, before), "failed compatibility preflight changed foreign inputs")
                ''')

    def test_product_collection_cannot_reintroduce_processing_scrap_or_an_extra_producer(self):
        self.lua.execute('''
          local all, selection = build(raw)
          local retained = {}
          for _, row in ipairs(all) do
            for _, expected in ipairs(expectations) do
              if row.name == expected.id then retained[#retained+1] = row end
            end
          end
          assert(#retained == 5, "missing paid SIF identity before product collection")
          raw.recipe["extra-plastic-producer"] = {name="extra-plastic-producer", type="recipe",
            results={{type="item",name="plastic-bar",amount=1}}}
          require("research.product_target_extension").extend(retained, values, {
            raw=raw,mods=mods,exact_product_target_families=selection.exact_product_target_families,
            exact_product_bindings=selection.exact_product_bindings,
          })
          for _, row in ipairs(retained) do
            local expected
            for _, candidate in ipairs(expectations) do if candidate.id == row.name then expected = candidate end end
            local found = {}
            for _, effect in ipairs(row.effects) do
              assert(expected.recipes[effect.recipe] and not found[effect.recipe], "collector added an unpaid effect")
              found[effect.recipe] = true
            end
            for recipe in pairs(expected.recipes) do assert(found[recipe], "collector removed a paid effect") end
          end
        ''')

    def test_changed_native_binding_or_scope_refuses_the_retention(self):
        for scenario in ["owner", "missing-recipe", "extra-recipe", "effect-type", "duplicate-family"]:
            with self.subTest(scenario=scenario):
                self.lua.globals().scenario = scenario
                self.lua.execute('''
                  local selected = catalogue.select(mods, raw)
                  local bound
                  for _, binding in ipairs(selected.native_owners) do
                    if binding.family == "research_plastic" then bound = binding end
                  end
                  assert(bound)
                  if scenario == "owner" then bound.id = "unrelated-owner"
                  elseif scenario == "missing-recipe" then table.remove(bound.admission.recipes)
                  elseif scenario == "extra-recipe" then bound.admission.recipes[#bound.admission.recipes+1] = "unpaid-recipe"
                  elseif scenario == "effect-type" then bound.admission.effect_type = "laboratory-speed"
                  else selected.native_owners[#selected.native_owners+1] = clone(bound) end
                  local before = clone(raw)
                  local ok, message = pcall(modern.preflight_native_owner_patches, selected, raw, values)
                  assert(not ok and string.find(message, "MIR SIF retained", 1, true),
                    "wrong current native binding admitted")
                  assert(same(raw, before), "failed binding check changed foreign prototypes")
                ''')

    def test_each_selection_is_detached_and_nondefault_tuning_uses_the_existing_setting(self):
        self.lua.execute('''
          local first = catalogue.select(mods)
          assert(first.sif_retained and #first.sif_retained == 5, "missing paid SIF selection")
          first.sif_retained[1].effects[1].recipe = "caller-mutated"
          local second = catalogue.select(mods)
          assert(second.sif_retained[1].effects[1].recipe ~= "caller-mutated", "retained descriptor alias leaked")
          values.streams.research_plastic.effect_percent = 7
          local rows = modern.technologies(second, values)
          for _, row in ipairs(rows) do
            if row.name == "recipe-prod-research_plastic-1" then
              assert(row.hidden == true and #row.effects == 2)
              for _, effect in ipairs(row.effects) do assert(math.abs(effect.change-.07) < 1e-12) end
              return
            end
          end
          error("missing paid SIF plastic after configured build")
        ''')

    def test_named_owner_effects_are_scanned_once_per_preflight(self):
        self.lua.execute('''
          local scans = {}
          for name, owner in pairs(raw.technology) do
            local effects, id = owner.effects, name
            owner.effects = setmetatable({}, {__ipairs=function()
              scans[id] = (scans[id] or 0) + 1
              return ipairs(effects)
            end})
          end
          build(raw)
          local count = 0
          for name in pairs(raw.technology) do
            count = count + 1
            assert(scans[name] == 1, "named native owner was rescanned or omitted: " .. name)
          end
          assert(count == 6)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SIFRetainedManufacturingTests))
    sys.exit(0 if result.wasSuccessful() else 1)
