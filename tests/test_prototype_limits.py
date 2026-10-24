"""Opposing Lua 5.2 controls for the optional prototype-limit group."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PrototypeLimitsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          limits = require("overrides.prototype_limits")
          scope = require("overrides.recycling_scope")
          function options(cap, scoped, chance)
            return {["mir-prototype-productivity-cap"] = cap,
              ["mir-productivity-cap-self-recycling-only"] = scoped,
              ["mir-recycling-return-chance"] = chance}
          end
          function manufacture(product, input)
            return {ingredients = {{input or "ore", 1}}, results = {{product or "component", 1}}}
          end
          function reclaim(fields, input, extra)
            local result = {name = "component"}
            for key, value in pairs(fields) do result[key] = value end
            local recipe = {ingredients = {{"component", input or 1}}, results = {result}}
            for key, value in pairs(extra or {}) do recipe[key] = value end
            return recipe
          end
        ''')

    def test_defaults_never_read_raw_or_import_scope(self):
        self.lua.execute('''
          package.loaded["overrides.recycling_scope"] = nil
          local raw = setmetatable({}, {__index = function() error("inactive read") end,
            __pairs = function() error("inactive traversal") end})
          local result = limits.apply(raw, {})
          assert(result.indexed_recipes == 0 and result.productivity == 0)
          assert(package.loaded["overrides.recycling_scope"] == nil)
        ''')

    def test_receiver_ranges_detach_and_preserve_foreign_fields(self):
        self.lua.execute('''
          local shared = {speed_limits = {low = -0.6, high = 2, foreign = 7},
            consumption_limits = {low = -0.2}, bonus = {native = true}}
          local assembler, lab = {effect_receiver = shared}, {effect_receiver = shared}
          local raw = {["assembling-machine"] = {a = assembler}, lab = {l = lab},
            unrelated = setmetatable({}, {__pairs = function() error("unrelated enumeration") end})}
          local changed = limits.apply(raw, {["mir-prototype-speed-cap"] = "bonus-400",
            ["mir-prototype-efficiency-cap"] = "saving-9999",
            ["mir-prototype-speed-floor"] = "saving-999",
            ["mir-prototype-quality-cap"] = "bonus-250"})
          assert(changed.receivers == 8)
          assert(assembler.effect_receiver ~= shared and lab.effect_receiver ~= shared)
          assert(assembler.effect_receiver ~= lab.effect_receiver)
          assert(shared.speed_limits.high == 2 and shared.speed_limits.low == -0.6)
          local receiver = assembler.effect_receiver
          assert(receiver.speed_limits.low == -0.999 and receiver.speed_limits.high == 4)
          assert(receiver.speed_limits.foreign == 7 and receiver.bonus.native)
          assert(receiver.consumption_limits.low == -0.9999 and receiver.consumption_limits.high == 1000)
          assert(receiver.quality_limits.low == 0 and receiver.quality_limits.high == 2.5)
        ''')

    def test_global_cap_preserves_recycling_parameter_and_other_fields(self):
        self.lua.execute('''
          local raw = {recipe = {a = {foreign = 1}, b = {category = "recycling", maximum_productivity = 2},
            c = {categories = {"crafting", "recycling"}, maximum_productivity = 1},
            d = {parameter = true}, e = {category = "recycling", categories = {"crafting"}}}}
          local result = limits.apply(raw, options("percent-400", true))
          assert(result.productivity == 2 and result.indexed_recipes == 5)
          assert(raw.recipe.a.maximum_productivity == 3 and raw.recipe.a.foreign == 1)
          assert(raw.recipe.b.maximum_productivity == 2 and raw.recipe.c.maximum_productivity == 1)
          assert(raw.recipe.d.maximum_productivity == nil and raw.recipe.e.maximum_productivity == 3)
          result = limits.apply(raw, options("percent-250", true))
          assert(result.indexed_recipes == 0 and result.productivity == 2)
          assert(raw.recipe.a.maximum_productivity == 2.5 and raw.recipe.e.maximum_productivity == 2.5)
        ''')

    def test_combined_receiver_limits_copy_each_changed_receiver_once(self):
        self.lua.execute('''
          local shared = {copy_work_marker=true, foreign={sentinel=17}}
          shared.self, shared.alias = shared, shared.foreign
          local assembler, lab = {effect_receiver=shared}, {effect_receiver=shared}
          local raw = {["assembling-machine"]={assembler}, lab={lab},
            unrelated=setmetatable({}, {__pairs=function() error("unrelated scan") end})}
          local options = {["mir-prototype-efficiency-cap"]="saving-90",
            ["mir-prototype-pollution-cap"]="saving-95",
            ["mir-prototype-speed-floor"]="saving-999",
            ["mir-prototype-speed-cap"]="bonus-400",
            ["mir-prototype-quality-cap"]="bonus-250"}
          local original_pairs, copies = pairs, 0
          pairs = function(value)
            if type(value) == "table" and rawget(value, "copy_work_marker") then
              copies = copies + 1
            end
            return original_pairs(value)
          end
          local ok, facts = pcall(limits.apply, raw, options)
          pairs = original_pairs
          assert(ok, facts)
          assert(copies == 2, "receiver copied " .. copies .. " times for two changed prototypes")
          assert(facts.receivers == 10, "retain the count of changed limit fields")
          assert(shared.speed_limits == nil and shared.foreign.sentinel == 17)
          for _, prototype in ipairs({assembler, lab}) do
            local receiver = prototype.effect_receiver
            assert(receiver ~= shared and receiver.self == receiver)
            assert(receiver.foreign ~= shared.foreign and receiver.foreign == receiver.alias)
            assert(receiver.consumption_limits.low == -.9 and receiver.consumption_limits.high == 1000)
            assert(receiver.pollution_limits.low == -.95 and receiver.pollution_limits.high == 1000)
            assert(receiver.speed_limits.low == -.999 and receiver.speed_limits.high == 4)
            assert(receiver.quality_limits.low == 0 and receiver.quality_limits.high == 2.5)
          end
          assert(assembler.effect_receiver ~= lab.effect_receiver
            and assembler.effect_receiver.foreign ~= lab.effect_receiver.foreign)
          local current = assembler.effect_receiver
          facts = limits.apply(raw, options)
          assert(facts.receivers == 0 and assembler.effect_receiver == current,
            "unchanged receivers must retain their identity on repeated application")
        ''')

    def test_foreign_receiver_cycles_aliases_and_scalar_ranges(self):
        self.lua.execute('''
          local foreign = {}; foreign.self = foreign
          local shared = {first=foreign,second=foreign,speed_limits="foreign-scalar"}
          local machine = {effect_receiver=shared}
          local facts = limits.apply({lab={machine}}, {["mir-prototype-speed-cap"]="bonus-200"})
          assert(facts.receivers == 1)
          local out = machine.effect_receiver
          assert(out ~= shared and out.first ~= foreign and out.first == out.second)
          assert(out.first.self == out.first and foreign.self == foreign)
          assert(shared.speed_limits == "foreign-scalar")
          assert(out.speed_limits.low == -0.8 and out.speed_limits.high == 2)
        ''')

    def test_deep_foreign_receiver_detaches_with_bounded_call_depth(self):
        self.lua.execute('''
          local shared, key = {}, {}
          shared.foreign = {[key]=key}
          local cursor = shared.foreign
          for index = 1, 4096 do cursor.child = {}; cursor = cursor.child end
          cursor.self = cursor
          local machine = {effect_receiver=shared}
          debug.sethook(function()
            if debug.getinfo(96, "f") then error("receiver copy grew the Lua call stack") end
          end, "c")
          local ok, result = pcall(limits.apply, {lab={machine}},
            {["mir-prototype-speed-cap"]="bonus-200"})
          debug.sethook()
          assert(ok, result)
          assert(result.receivers == 1 and shared.speed_limits == nil)
          assert(machine.effect_receiver.speed_limits.high == 2)
          local original, copied = shared.foreign, machine.effect_receiver.foreign
          local copied_key, copied_value = next(copied)
          if copied_key == "child" then copied_key, copied_value = next(copied, copied_key) end
          assert(type(copied_key) == "table" and copied_key ~= key and copied_key == copied_value)
          for index = 1, 4096 do
            assert(copied ~= original)
            original, copied = original.child, copied.child
          end
          assert(copied ~= original and copied.self == copied and original.self == original)
        ''')

    def test_return_bounds_exclusions_probabilities_and_native_caps(self):
        self.lua.execute('''
          local cases = {
            {10, {amount=8,probability=0.5,ignored_by_productivity=2}, 2},
            {4, {amount=4,probability=0.25,ignored_by_productivity=1}, 4},
            {4, {amount=2,amount_min=10,amount_max=99}, 1},
            {8, {amount_min=4,amount_max=2}, 1},
            {2, {amount=2,probability=0.5,ignored_by_stats=1}, 2},
            {2, {amount=2,probability=0.5,ignored_by_stats=1,ignored_by_productivity=0}, 1},
            {2, {amount=2,probability=0.5,ignored_by_productivity=9}, math.huge},
            {2, {amount=2,probability=0}, math.huge},
            {1, {amount=1,probability=0.0000001}, 9999999},
            {1, {amount=1,probability=1e-309}},
            {2, {amount=2,independent_probability=0,probability=1}, math.huge},
            {4, {amount=4,independent_probability=0.5,shared_probability={min=0.2,max=0.7},ignored_by_productivity=1}, 4},
            {1, {amount=1}, 0},
            {2, {amount=1,extra_count_fraction=0}, 1},
            {2, {amount=1,extra_count_fraction=0.5}},
            {2, {amount=1,extra_count_fraction="invalid"}},
            {2, {amount=1,ignored_by_productivity=-1}},
            {2, {amount=1,independent_probability="invalid"}},
            {2, {amount=1,shared_probability={min=-1,max=0}}},
            {2, {amount=1,shared_probability=0.5}},
            {2, {amount=math.huge}},
            {2, {amount=1,probability=0/0}},
            {1, {amount=2,ignored_by_productivity=2}}
          }
          for index, case in ipairs(cases) do
            local recipes = {make = manufacture(), back = reclaim(case[2], case[1])}
            local classifier = scope.build(recipes, 3, true)
            local actual = classifier.maximum_safe_productivity("back")
            assert(actual == case[3] or actual and case[3] and math.abs(actual-case[3]) < 0.000001,
              "wrong bound " .. index .. ": " .. tostring(actual))
            assert(classifier.approve("make") == (case[3] ~= nil), "admission " .. index)
            limits.apply({recipe = recipes}, options("percent-10000", true))
            assert(recipes.make.maximum_productivity == (case[3] and 100 or 3), "forward " .. index)
            assert(recipes.back.maximum_productivity == math.min(3, case[3] or 3), "return " .. index)
          end
          local recipes = {make = manufacture(), back = reclaim({amount=1,probability=0.5}, 1,
            {category="recycling", maximum_productivity=3})}
          assert(not scope.build(recipes, 3, true).approve("make"))
          recipes.back.maximum_productivity = 1
          assert(scope.build(recipes, 3, true).approve("make"))
          limits.apply({recipe=recipes}, options("percent-10000", true))
          assert(recipes.back.maximum_productivity == 1 and recipes.make.maximum_productivity == 100)
          recipes.back.maximum_productivity = nil
          assert(not scope.build(recipes, 4, true).approve("make"))
        ''')

    def test_cycles_byproducts_ambiguity_and_variants_withhold_increase(self):
        self.lua.execute('''
          local function baseline()
            return {make = manufacture(), back = reclaim({amount=1,probability=0.25})}
          end
          local recipes = baseline()
          assert(scope.build(recipes,3,true).approve("make"))
          recipes.to_intermediate = manufacture("intermediate", "component")
          recipes.to_ore = manufacture("ore", "intermediate")
          assert(not scope.build(recipes,3,true).approve("make"))
          recipes = baseline(); recipes.back.results[2] = {"byproduct",1}
          assert(not scope.build(recipes,3,true).approve("make"))
          recipes = baseline(); recipes.other = reclaim({amount=1,probability=0.1})
          assert(not scope.build(recipes,3,true).approve("make"))
          recipes = baseline(); recipes.make.ingredients = {{"component",1}}
          assert(not scope.build(recipes,3,true).approve("make"))
          recipes = baseline(); recipes.make.results[1] = {type="fluid",name="component",amount=1}
          assert(not scope.build(recipes,3,true).approve("make"))
          recipes = baseline(); recipes.make.normal = manufacture(); recipes.make.expensive = manufacture()
          assert(not scope.build(recipes,3,true).approve("make"))
        ''')

    def test_recycling_changes_only_generated_item_rolls_and_keeps_native_caps(self):
        self.lua.execute('''
          local original = {name="component", amount=8, probability=0.25, foreign=9}
          local generated = {category="recycling",hidden=true,unlock_results=false,
            maximum_productivity=0.5,ingredients={{"component",1}},results={original,
              {type="fluid",name="water",amount=1,probability=0.5},
              {name="shared",amount=1,shared_probability={min=0,max=0.5}}}}
          local visible = {category="recycling",ingredients={{"component",1}},results={{name="component",amount=1}}}
          local facts = limits.apply({recipe={generated=generated,visible=visible}},
            options("percent-400",false,"match-productivity-cap"))
          local output = generated.results[1]
          assert(facts.recycling_products == 1 and output.independent_probability == 0.2)
          assert(output.probability == nil and output.amount == 8 and output.foreign == 9)
          assert(original.probability == .25 and original.independent_probability == nil)
          assert(generated.maximum_productivity == 0.5 and visible.maximum_productivity == nil)
          assert(generated.results[2].probability == 0.5 and generated.results[3].independent_probability == nil)
          assert(visible.results[1].independent_probability == nil)
        ''')

    def test_recycling_shared_results_do_not_compound_or_change_excluded_recipes(self):
        self.lua.execute('''
          local target = require("platform.target")
          for _, field in ipairs({"probability", "independent_probability"}) do
            target.recipe_probability = field
            local product = {name="component",amount=8,probability=.25,foreign=17}
            local shared = {product}
            local function recycling_recipe(results)
              return {category="recycling",hidden=true,unlock_results=false,
                ingredients={{"component",1}},results=results}
            end
            local first, second = recycling_recipe(shared), recycling_recipe({product})
            local visible, parameter = recycling_recipe(shared), recycling_recipe(shared)
            visible.hidden, parameter.parameter = false, true
            local ordinary = {ingredients={{"component",1}},results=shared}
            local raw = {recipe={first=first,second=second,visible=visible,
              parameter=parameter,ordinary=ordinary}}
            local facts = limits.apply(raw, options("engine-default",false,"percent-20"))
            assert(facts.recycling_products == 2)
            for _, recipe in ipairs({first,second}) do
              assert(math.abs(recipe.results[1][field] - .2) < 1e-12,
                "shared recycling product compounded the return multiplier")
              assert(recipe.results[1].amount == 8 and recipe.results[1].foreign == 17)
            end
            assert(first.results ~= shared and second.results[1] ~= product)
            assert(first.results[1] ~= second.results[1])
            assert(product.probability == .25 and product.independent_probability == nil,
              "recycling override modified an excluded recipe's shared product")
            assert(visible.results == shared and parameter.results == shared and ordinary.results == shared)
          end
        ''')

    def test_recycling_shared_difficulty_variants_keep_excluded_owner_unchanged(self):
        self.lua.execute('''
          local variant = {ingredients={{"component",1}},
            results={{name="component",amount=8,probability=.25}},foreign=17}
          local selected = {category="recycling",hidden=true,unlock_results=false,
            normal=variant,expensive=variant}
          local excluded = {category="recycling",normal=variant,expensive=variant}
          local facts = limits.apply({recipe={selected=selected,excluded=excluded}},
            options("engine-default",false,"percent-20"))
          assert(facts.recycling_products == 2)
          for _, row in ipairs({selected.normal,selected.expensive}) do
            assert(math.abs(row.results[1].independent_probability - .2) < 1e-12,
              "shared difficulty variant compounded the return multiplier")
            assert(row ~= variant and row.foreign == 17)
          end
          assert(excluded.normal == variant and excluded.expensive == variant)
          assert(variant.results[1].probability == .25 and variant.results[1].independent_probability == nil)
        ''')

    def test_power_floor_touches_only_explicit_zero_watts(self):
        self.lua.execute('''
          local group = {a={energy_usage="0kW"},b={energy_usage=" -0.0 MW "},c={energy_usage=0},
            d={energy_usage="1W"},e={energy_usage="0J"},f={},g={energy_usage="bad"},h={energy_usage=-1}}
          local facts = limits.apply({foreign=group}, {["mir-prototype-positive-power-floor"]=true})
          assert(facts.positive_power == 3)
          assert(group.a.energy_usage == "1W" and group.b.energy_usage == "1W" and group.c.energy_usage == "1W")
          assert(group.d.energy_usage == "1W" and group.e.energy_usage == "0J" and group.f.energy_usage == nil)
          assert(group.g.energy_usage == "bad" and group.h.energy_usage == -1)
        ''')

    def test_f200_recycling_uses_its_native_probability_field_and_preserves_zero(self):
        self.lua.execute('''
          local target = require("platform.target")
          target.recipe_probability, target.receiver_limits = "probability", false
          local result = {name="component", amount=8, probability=0.25, foreign=9}
          local zero = {name="component", amount=8, probability=0}
          local recipe = {category="recycling", hidden=true, unlock_results=false,
            ingredients={{"component",1}}, results={result,zero}}
          local facts = limits.apply({recipe={back=recipe}}, options("engine-default",false,"percent-20"))
          assert(facts.recycling_products == 1 and recipe.results[1].probability == 0.2)
          assert(recipe.results[1].independent_probability == nil and recipe.results[1].foreign == 9)
          assert(result.probability == .25 and result.independent_probability == nil)
          assert(zero.probability == 0 and zero.independent_probability == nil)
          assert(limits.apply({recipe={back=recipe}}, options(nil,false,"percent-25")).recycling_products == 0)
        ''')

    def test_f200_productivity_also_inherits_the_stats_exclusion(self):
        self.lua.execute('''
          local target = require("platform.target")
          target.recipe_probability, target.productivity_ignores_stats = "probability", true
          target.receiver_limits = false
          local recipes = {make=manufacture(),back=reclaim({amount=2,probability=0.5,ignored_by_stats=1},2)}
          local facts = limits.apply({recipe=recipes}, options("percent-10000",true))
          assert(facts.indexed_recipes == 2 and recipes.back.maximum_productivity == 2)
          assert(recipes.make.maximum_productivity == 100)
          assert(recipes.back.results[1].ignored_by_productivity == nil)
        ''')

    def test_fixed_receiver_limits_are_reported_without_inventing_native_fields(self):
        self.lua.execute('''
          local target = require("platform.target")
          target.recipe_probability, target.receiver_limits = "probability", false
          local raw = setmetatable({}, {__index=function() error("unsupported receiver read") end,
            __pairs=function() error("unsupported receiver enumeration") end})
          local facts = limits.apply(raw, {["mir-prototype-speed-cap"]="bonus-400",
            ["mir-prototype-efficiency-cap"]="saving-9999"})
          assert(facts.unsupported_receiver_limits == 2 and facts.receivers == 0)
          local foreign = {uses_module_effects=false, base_effect={speed=0.2}}
          local lab = {effect_receiver=foreign}
          facts = limits.apply({lab={lab}}, {["mir-prototype-quality-cap"]="bonus-250"})
          assert(facts.unsupported_receiver_limits == 1 and facts.receivers == 0)
          assert(lab.effect_receiver == foreign and foreign.quality_limits == nil)
          assert(foreign.base_effect.speed == 0.2 and foreign.uses_module_effects == false)
        ''')

    def test_scope_indexes_recipes_once_and_preserves_modern_exclusion_default(self):
        self.lua.execute('''
          local recipes = {make=manufacture(),back=reclaim({amount=2,probability=0.5,ignored_by_stats=1},2)}
          for i=1,1000 do recipes["unrelated"..i] = manufacture("product"..i,"input"..i) end
          local classifier = scope.build(recipes,3,true)
          assert(classifier.visited == 1002 and classifier.maximum_safe_productivity("back") == 2)
          for i=1,250 do assert(classifier.approve("make")) end
          assert(classifier.visited == 1002)
          assert(scope.build(recipes,3,false).maximum_safe_productivity("back") == 1)
        ''')


    def test_pipeline_extent_preserves_percentages_and_portable_numeric_meaning(self):
        self.lua.execute('''
          local pipeline = require("overrides.pipeline_extent")
          for percent, expected in pairs({['25']=.25,['50']=.5,['75']=.75,
            ['100']=1,['125']=1.25,['150']=1.5,['200']=2,['250']=2.5,
            ['300']=3,['400']=4,['500']=5,['750']=7.5,['1000']=10}) do
            assert(pipeline.multiplier(percent) == expected)
          end
          assert(pipeline.multiplier(2) == .02 and pipeline.multiplier("2") == 2)
          assert(pipeline.multiplier("12.5") == .125 and pipeline.multiplier(100) == 1)
          assert(pipeline.multiplier(nil) == 1 and pipeline.multiplier("invalid") == 1)
          assert(pipeline.multiplier(0/0) == 1 and pipeline.multiplier(math.huge) == 1)
          local raw = setmetatable({}, {__pairs=function() error("inactive pipeline traversal") end})
          assert(pipeline.apply(raw, "100") == 0 and pipeline.apply(raw, nil) == 0)
        ''')

    def test_pipeline_extent_scales_every_delivered_box_field_once_with_rounding_and_bounds(self):
        self.lua.execute('''
          local pipeline = require("overrides.pipeline_extent")
          local shared = {max_pipeline_extent=321,foreign="preserve"}
          local a, b, c, d = {}, {max_pipeline_extent=1}, {max_pipeline_extent=4294967295},
            {max_pipeline_extent=7}
          local prototype = {fluid_box=shared, input_fluid_box=a, output_fluid_box=b,
            energy_source={fuel_fluid_box=c,oxidizer_fluid_box=d},
            fluid_boxes={shared},unrelated={max_pipeline_extent=17}}
          prototype.cycle=prototype
          assert(pipeline.apply({fixture={a=prototype,b=prototype}}, "150") == 5)
          assert(shared.max_pipeline_extent == 482 and shared.foreign == "preserve")
          assert(a.max_pipeline_extent == 480 and b.max_pipeline_extent == 2)
          assert(c.max_pipeline_extent == 4294967295 and d.max_pipeline_extent == 11)
          assert(prototype.unrelated.max_pipeline_extent == 17)
          local tiny={fluid_box={max_pipeline_extent=1}}
          assert(pipeline.apply(tiny,"25") == 1 and tiny.fluid_box.max_pipeline_extent == 1)
        ''')

    def test_pipeline_extent_deep_shared_cycles_use_bounded_call_depth_and_one_visit(self):
        self.lua.execute('''
          local pipeline = require("overrides.pipeline_extent")
          local shared = {max_pipeline_extent=321}
          local raw = {input_fluid_box=shared}
          local cursor, visits = raw, {}
          for index = 1, 4096 do
            local node = setmetatable({}, {__pairs=function(value)
              assert(visits[value] == nil, "prototype node visited twice")
              visits[value] = true
              return next, value, nil
            end})
            cursor.child = node
            cursor = node
          end
          cursor.parent = raw
          cursor.fluid_box = shared
          cursor.fluid_boxes = {shared, {max_pipeline_extent=7}}
          debug.sethook(function()
            if debug.getinfo(96, "f") then error("pipeline walk grew the Lua call stack") end
          end, "c")
          local ok, count = pcall(pipeline.apply, raw, "150")
          debug.sethook()
          assert(ok, count)
          assert(count == 2 and shared.max_pipeline_extent == 482)
          assert(cursor.fluid_boxes[2].max_pipeline_extent == 11)
          local visited = 0
          for _ in pairs(visits) do visited = visited + 1 end
          assert(visited == 4096)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PrototypeLimitsTests))
    sys.exit(0 if result.wasSuccessful() else 1)
