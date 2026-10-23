"""Pure controls for bounded typed product-to-family target collection."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"


class ProductTargetTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          targets = require("compatibility.product_targets")

          function product(kind, name, fields)
            local row = {type=kind, name=name, amount=1}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end
          function recipe(ingredients, results, fields)
            local row = {ingredients=ingredients or {}, results=results or {}}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end
          function binding(family, weight, products, fields)
            local row = {family=family, weight=weight, products=products}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end
          function target_names(rows)
            local values = {}
            for _, row in ipairs(rows or {}) do
              values[#values + 1] = row.family .. ":" .. row.recipe .. ":"
                .. row.product_type .. ":" .. row.product_name .. ":" .. tostring(row.weight)
            end
            return table.concat(values, ",")
          end
          function frozen_copy(value, seen)
            if type(value) ~= "table" then return tostring(value) end
            seen = seen or {}
            if seen[value] then return "cycle" end
            seen[value] = true
            local keys = {}
            for key in pairs(value) do keys[#keys+1] = tostring(key) end
            table.sort(keys)
            local out = {}
            for _, text in ipairs(keys) do
              local key = tonumber(text) or text
              out[#out+1] = text .. "=" .. frozen_copy(value[key], seen)
            end
            seen[value] = nil
            return table.concat(out, "|")
          end
        ''')

    def test_typed_lookup_preserves_weights_and_target_order(self):
        self.lua.execute(r'''
          local context = targets.prepare({
            binding("copper", .10, {{type="item", name="copper-plate"}}),
            binding("water", .02, {{type="fluid", name="water"}}),
            binding("gears", .05, {{type="item", name="iron-gear-wheel"}}),
          })
          local recipes = {
            z_gear = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}),
            b_copper = recipe({}, {product("item", "copper-plate")}),
            a_water = recipe({}, {product("fluid", "water")}),
            item_water = recipe({}, {product("item", "water")}),
          }
          local result = targets.collect(recipes, context)
          assert(target_names(result.targets) ==
            "copper:b_copper:item:copper-plate:0.1,gears:z_gear:item:iron-gear-wheel:0.05,water:a_water:fluid:water:0.02")
          assert(target_names(result.by_family.water) == "water:a_water:fluid:water:0.02")
          assert(result.work.recipes == 4 and result.work.products == 4 and result.work.matches == 3)
        ''')

    def test_group_order_deduplicates_one_recipe_without_losing_authored_weight(self):
        self.lua.execute(r'''
          local context = targets.prepare({
            binding("parts", .10, {{type="item", name="common-part"}}),
            binding("parts", .02, {{type="item", name="rare-part"}}),
            binding("other", .04, {{type="item", name="rare-part"}}),
          })
          local result = targets.collect({mixed=recipe({}, {
            product("item", "rare-part"), product("item", "common-part")
          })}, context)
          assert(target_names(result.targets) ==
            "other:mixed:item:rare-part:0.04,parts:mixed:item:common-part:0.1")
          assert(#result.by_family.parts == 1 and result.work.matches == 3)
        ''')

    def test_blocked_earlier_group_does_not_claim_a_valid_later_group_recipe(self):
        self.lua.execute(r'''
          local context = targets.prepare({
            binding("parts", .10, {{type="item",name="common-part"}},
              {exclude_recipe_patterns={"^mixed$"}}),
            binding("parts", .02, {{type="item",name="rare-part"}}),
          })
          local result = targets.collect({mixed=recipe({}, {
            product("item","common-part"),product("item","rare-part")
          })}, context)
          assert(target_names(result.targets) == "parts:mixed:item:rare-part:0.02")
        ''')

    def test_known_exclusions_and_return_controls_remain_per_binding(self):
        self.lua.execute(r'''
          local ordinary = binding("plate", .1, {{type="item", name="plate"}},
            {exclude_ingredient_patterns={"scrap"}})
          local recycling = binding("recycling-plate", .2, {{type="item", name="plate"}},
            {include_recycling=true, exclude_ingredient_patterns={"scrap"}})
          local return_allowed = binding("return-plate", .3, {{type="item", name="plate"}},
            {allow_shared_input_output=true, include_recycling=true, exclude_ingredient_patterns={"scrap"}})
          local context = targets.prepare({ordinary, recycling, return_allowed})
          local result = targets.collect({
            ordinary = recipe({{"ore",1}}, {product("item","plate")}),
            scrap = recipe({{"scrap",1}}, {product("item","plate")}),
            recycle = recipe({{"ore",1}}, {product("item","plate")}, {category="recycling"}),
            returned = recipe({{"plate",1}}, {product("item","plate",{catalyst_amount=1})}),
            hidden = recipe({{"ore",1}}, {product("item","plate")}, {hidden=true}),
          }, context)
          assert(target_names(result.by_family.plate) == "plate:ordinary:item:plate:0.1")
          assert(target_names(result.by_family["recycling-plate"]) ==
            "recycling-plate:ordinary:item:plate:0.2,recycling-plate:recycle:item:plate:0.2")
          assert(target_names(result.by_family["return-plate"]) ==
            "return-plate:ordinary:item:plate:0.3,return-plate:recycle:item:plate:0.3,return-plate:returned:item:plate:0.3")
          assert(result.by_family.plate[2] == nil)
        ''')

    def test_probability_ranges_and_productivity_exclusions_are_local_yield_gates(self):
        self.lua.execute(r'''
          local rows = {
            zero_independent = recipe({}, {product("item","target",{independent_probability=0})}),
            zero_legacy = recipe({}, {product("item","target",{probability=0})}),
            legacy_positive = recipe({}, {product("item","target",{probability=.5})}),
            fully_ignored = recipe({}, {product("item","target",{ignored_by_productivity=1})}),
            partial_ignored = recipe({}, {product("item","target",{amount=2, ignored_by_productivity=1})}),
            ranged = recipe({}, {{type="item", name="target", amount_min=0, amount_max=1}}),
            zero_range = recipe({}, {{type="item", name="target", amount_min=0, amount_max=0}}),
            invalid_range = recipe({}, {{type="item", name="target", amount_min=2, amount_max=1}}),
            stats_only = recipe({}, {product("item","target",{ignored_by_stats=1})}),
          }
          local rules = {binding("target", .1, {{type="item", name="target"}})}
          local regular = targets.collect(rows, targets.prepare(rules))
          assert(target_names(regular.by_family.target) ==
            "target:partial_ignored:item:target:0.1,target:ranged:item:target:0.1")
          local legacy = targets.collect(rows, targets.prepare(rules, {
            probability_field="probability", productivity_ignores_stats=false}))
          assert(target_names(legacy.by_family.target) ==
            "target:legacy_positive:item:target:0.1,target:partial_ignored:item:target:0.1,"
            .. "target:ranged:item:target:0.1,target:stats_only:item:target:0.1")
          local inherited = targets.collect(rows, targets.prepare(rules, {productivity_ignores_stats=true}))
          assert(target_names(inherited.by_family.target) ==
            "target:partial_ignored:item:target:0.1,target:ranged:item:target:0.1")
        ''')

    def test_unsupported_shapes_and_explicit_productivity_denial_withhold_only_that_recipe(self):
        self.lua.execute(r'''
          local strict = binding("target", .1, {{type="item", name="target"}},
            {reject_explicit_productivity_denial=true})
          local result = targets.collect({
            valid = recipe({}, {product("item", "target")}),
            wrong_type = recipe({}, {product("virtual", "target")}),
            malformed = recipe({}, {"target"}),
            denied = recipe({}, {product("item", "target")}, {allow_productivity=false}),
            variants = {normal={ingredients={}, results={product("item", "target")}},
              expensive={ingredients={}, results={product("item", "target")}}},
          }, targets.prepare({strict}))
          assert(target_names(result.targets) ==
            "target:valid:item:target:0.1,target:variants:item:target:0.1")
          local ok = pcall(function() targets.prepare({binding("bad", .1, {{type="item", name="x"}},
            {exclude_recipe_patterns={"["}})}) end)
          assert(not ok)
        ''')

    def test_collection_is_linear_in_recipe_products_and_never_mutates_raw_rows(self):
        self.lua.execute(r'''
          local recipes = {
            first = recipe({{"ore",1}}, {product("item", "target")}),
            second = recipe({{"ore",1}}, {product("item", "target")}),
          }
          for index=1,200 do
            recipes["unrelated-" .. index] = recipe({{"feed-" .. index, 1}},
              {product("item", "other-" .. index)})
          end
          local before = frozen_copy(recipes)
          local context = targets.prepare({binding("target", .1, {{type="item", name="target"}})})
          local result = targets.collect(recipes, context)
          assert(target_names(result.by_family.target) ==
            "target:first:item:target:0.1,target:second:item:target:0.1")
          assert(result.work.recipes == 202 and result.work.products == 202
            and result.work.ingredients == 202 and result.work.matches == 2)
          assert(frozen_copy(recipes) == before)
        ''')

    def test_expensive_only_variant_is_not_lost_at_a_sparse_normal_slot(self):
        self.lua.execute(r'''
          local result = targets.collect({
            expensive_only={expensive={ingredients={}, results={product("item", "target")}}},
          }, targets.prepare({binding("target", .1, {{type="item", name="target"}})}))
          assert(target_names(result.targets) == "target:expensive_only:item:target:0.1")
          assert(result.work.products == 1 and result.work.recipes == 1)
        ''')

    def test_patterns_resolve_native_item_classes_once_with_typed_and_group_precedence(self):
        self.lua.execute(r'''
          local reads = 0
          local items = {['common-drill']={}, ['custom-drill']={}, other={}}
          setmetatable(items, {__pairs=function(value) reads=reads+1; return next,value,nil end})
          local raw = {item=items, ammo={['special-shell']={}}, fluid={['fluid-drill']={}}}
          local rules = {
            binding('drills',1,{{type='item',name='common-drill'}}),
            binding('drills',.25,{}, {item_patterns={'%-drill$'}}),
            binding('ammo',.1,{}, {item_patterns={'%-shell$'}}),
          }
          local before = frozen_copy(rules)
          local context = targets.prepare(rules, {raw=raw})
          assert(reads == 1 and context.items == 4 and context.pattern_tests == 8)
          local recipes = {
            mixed=recipe({}, {product('item','custom-drill'), product('item','common-drill')}),
            custom=recipe({}, {product('item','custom-drill')}),
            ammo=recipe({}, {product('item','special-shell')}),
            wrong_type=recipe({}, {product('fluid','custom-drill')}),
            nonexistent=recipe({}, {product('item','absent-drill')}),
            fluid_only=recipe({}, {product('fluid','fluid-drill')}),
          }
          local result = targets.collect(recipes, context)
          assert(target_names(result.targets) == 'ammo:ammo:item:special-shell:0.1,'
            .. 'drills:custom:item:custom-drill:0.25,drills:mixed:item:common-drill:1')
          assert(reads == 1 and result.work.products == 7 and result.work.items == 4)
          assert(frozen_copy(rules) == before)
          rules[2].item_patterns[1]='other'
          raw.item['late-drill']={}
          assert(context.items == 4 and #context.rules[2].products == 2)
        ''')

    def test_literal_rules_never_read_native_item_classes_and_invalid_patterns_fail_before_scan(self):
        self.lua.execute(r'''
          local raw=setmetatable({}, {__index=function() error('unexpected native class read') end})
          local context=targets.prepare({binding('literal',1,{{name='x'}})}, {raw=raw})
          assert(context.items == 0 and context.pattern_tests == 0)
          assert(not pcall(function() targets.prepare({binding('bad',1,{}, {item_patterns={'['}})}, {raw=raw}) end))
          assert(not pcall(function() targets.prepare({binding('bad',1,{}, {item_patterns={[2]='x'}})}, {raw=raw}) end))
          assert(not pcall(function() targets.prepare({binding('bad',1,{}, {item_patterns={'x'}})}) end))
          assert(not pcall(function() targets.prepare({binding('bad',1,{})}, {raw=raw}) end))
        ''')

    def test_patterns_expand_insertion_independently_and_keep_one_product_pass(self):
        self.lua.execute(r'''
          local function run(reverse)
            local items={}
            if reverse then items['z-part']={}; items['a-part']={}
            else items['a-part']={}; items['z-part']={} end
            local recipes={}
            for index=1,300 do recipes[tostring(index)]=recipe({}, {product('item','z-part')}) end
            local result=targets.collect(recipes, targets.prepare({
              binding('parts',.1,{}, {item_patterns={'%-part$'}})
            }, {raw={item=items}}))
            assert(result.work.items == 2 and result.work.pattern_tests == 2)
            assert(result.work.recipes == 300 and result.work.products == 300)
            return target_names(result.targets)
          end
          assert(run(false) == run(true))
        ''')

    def test_prepare_rejects_ambiguous_or_sparse_authored_bindings(self):
        self.lua.execute(r'''
          assert(not pcall(function() targets.prepare({binding("x", 0, {{type="item", name="x"}})}) end))
          assert(not pcall(function() targets.prepare({binding("x", .1, {
            {type="item", name="same"}, {type="item", name="same"}
          })}) end))
          assert(not pcall(function() targets.prepare({[2]=binding("x", .1, {{type="item", name="x"}})}) end))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ProductTargetTests))
    sys.exit(0 if result.wasSuccessful() else 1)
