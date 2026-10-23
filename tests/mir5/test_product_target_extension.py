"""Pure controls for bounded product-target extension of MIR-generated technologies."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"


class ProductTargetExtensionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          extension = require("research.product_target_extension")

          function product(kind, name, fields)
            local row = {type = kind, name = name, amount = 1}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end

          function recipe(ingredients, results, fields)
            local row = {ingredients = ingredients or {}, results = results or {}}
            for key, value in pairs(fields or {}) do row[key] = value end
            return row
          end

          function productivity(recipe_name, change, extra)
            local row = {type = "change-recipe-productivity", recipe = recipe_name, change = change}
            for key, value in pairs(extra or {}) do row[key] = value end
            return row
          end

          function generated(family, effects, enabled)
            local row = {
              name = "recipe-prod-" .. family .. "-1",
              effects = effects,
              order = "p[" .. family .. "]",
              enabled = enabled,
            }
            if enabled == nil then row.enabled = true end
            return row
          end

          function effect_rows(effects)
            local rows = {}
            for _, effect in ipairs(effects) do
              rows[#rows + 1] = effect.type .. ":" .. effect.recipe .. ":" .. string.format("%.5f", effect.change)
            end
            return table.concat(rows, ",")
          end

          function raw_with_recipes(recipes)
            return {
              recipe = recipes,
              technology = setmetatable({}, {
                __index = function(_, key)
                  error("product target extension must not read raw technology " .. tostring(key))
                end,
                __pairs = function()
                  error("product target extension must not scan raw technologies")
                end,
              }),
            }
          end

          function values(gear_effect, furnace_effect, space_effect)
            return {
              effect_percent = gear_effect,
              streams = {
                research_furnace = {effect_percent = furnace_effect},
                research_bioflux = {effect_percent = space_effect},
              },
            }
          end

          function frozen_copy(value, seen)
            if type(value) ~= "table" then return tostring(value) end
            seen = seen or {}
            if seen[value] then return "cycle" end
            seen[value] = true
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
            local rows = {}
            for _, key in ipairs(keys) do
              rows[#rows + 1] = tostring(key) .. "=" .. frozen_copy(value[key], seen)
            end
            seen[value] = nil
            return table.concat(rows, "|")
          end

          function assert_result_shape(result)
            assert(type(result) == "table")
            assert(type(result.extended_effects) == "number" and type(result.families) == "number")
            assert(type(result.work) == "table")
          end
        ''')

    def test_base_and_active_space_age_literal_routes_extend_only_existing_generated_rows(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)}, false)
          local bioflux = generated("research_bioflux", {productivity("bioflux", .10)})
          local foreign = {name = "foreign-productivity", order = "foreign", effects = {productivity("foreign", .33)}}
          local technologies = {gear, bioflux, foreign}
          local recipes = {
            ["modded-gear-producer"] = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}),
            ["modded-bioflux-producer"] = recipe({}, {product("item", "bioflux")}),
          }
          local base = extension.extend(technologies, values(17, 20, 11), {
            raw = raw_with_recipes(recipes), mods = {}
          })
          assert_result_shape(base)
          assert(base.extended_effects == 1 and base.families == 1)
          assert(base.work.recipes == 2 and base.work.products == 2 and base.work.matches == 1)
          assert(#technologies == 3 and gear.enabled == false and foreign.order == "foreign")
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:modded-gear-producer:0.17000")
          assert(effect_rows(bioflux.effects) == "change-recipe-productivity:bioflux:0.10000")
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.33000")

          local active = extension.extend(technologies, values(17, 20, 11), {
            raw = raw_with_recipes(recipes), mods = {['space-age'] = '2.1.23'}
          })
          assert_result_shape(active)
          assert(active.extended_effects == 1 and active.families == 1)
          assert(active.work.recipes == 2 and active.work.products == 2 and active.work.matches == 2)
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:modded-gear-producer:0.17000")
          assert(effect_rows(bioflux.effects) ==
            "change-recipe-productivity:bioflux:0.10000,change-recipe-productivity:modded-bioflux-producer:0.11000")
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.33000")
        ''')

    def test_weighted_furnace_routes_scale_current_stream_setting_and_append_in_recipe_order(self):
        self.lua.execute(r'''
          local original = productivity("stone-furnace", .20, {note = "preserve"})
          local furnace = generated("research_furnace", {original})
          local technologies = {furnace}
          local recipes = {
            ["a-stone-furnace"] = recipe({}, {product("item", "stone-furnace")}),
            ["b-steel-furnace"] = recipe({}, {product("item", "steel-furnace")}),
            ["c-electric-furnace"] = recipe({}, {product("item", "electric-furnace")}),
          }
          local bindings = require("compatibility.product_bindings")
          local recipes_before, bindings_before = frozen_copy(recipes), frozen_copy(bindings)
          local result = extension.extend(technologies, values(10, 20, 10), {
            raw = raw_with_recipes(recipes),
            mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 3 and result.families == 1)
          assert(result.work.recipes == 3 and result.work.products == 3 and result.work.matches == 3)
          assert(original.note == "preserve" and furnace.effects[1] == original)
          assert(frozen_copy(recipes) == recipes_before and frozen_copy(bindings) == bindings_before)
          assert(effect_rows(furnace.effects) ==
            "change-recipe-productivity:stone-furnace:0.20000,"
            .. "change-recipe-productivity:a-stone-furnace:0.20000,"
            .. "change-recipe-productivity:b-steel-furnace:0.10000,"
            .. "change-recipe-productivity:c-electric-furnace:0.05000")
        ''')

    def test_exclusions_typed_homonyms_and_unsupported_literal_routes_do_not_widen_productivity(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)})
          local explosives = generated("research_explosives", {productivity("explosives", .10)})
          local technologies = {gear, explosives}
          local result = extension.extend(technologies, values(10, 20, 10), {
            raw = raw_with_recipes({
              valid = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}),
              scrap = recipe({{"scrap", 1}}, {product("item", "iron-gear-wheel")}),
              recycling = recipe({{"iron-plate", 2}}, {product("item", "iron-gear-wheel")}, {category = "recycling"}),
              returned = recipe({{"iron-gear-wheel", 1}}, {product("item", "iron-gear-wheel", {catalyst_amount = 1})}),
              ignored = recipe({}, {product("item", "iron-gear-wheel", {ignored_by_productivity = 1})}),
              fluid_homonym = recipe({}, {product("fluid", "iron-gear-wheel")}),
              malformed = {ingredients = {}, results = "not-an-array"},
              bio_explosives = recipe({}, {product("item", "bio-explosives")}),
            }),
            mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 1 and result.families == 1)
          assert(result.work.recipes == 8 and result.work.products == 7 and result.work.matches == 4)
          assert(effect_rows(gear.effects) ==
            "change-recipe-productivity:iron-gear-wheel:0.10000,change-recipe-productivity:valid:0.10000")
          assert(effect_rows(explosives.effects) == "change-recipe-productivity:explosives:0.10000")
        ''')

    def test_extension_uses_one_recipe_product_pass_across_families_and_never_touches_raw_or_foreign_rows(self):
        self.lua.execute(r'''
          local gear = generated("research_gears", {productivity("iron-gear-wheel", .10)})
          local furnace = generated("research_furnace", {productivity("stone-furnace", .20)})
          local foreign = {name = "foreign", effects = {productivity("foreign", .50)}}
          local recipes = {
            gear_route = recipe({}, {product("item", "iron-gear-wheel")}),
            furnace_route = recipe({}, {product("item", "stone-furnace")}),
          }
          for index = 1, 100 do
            recipes["unrelated-" .. index] = recipe({}, {product("item", "other-" .. index)})
          end
          local recipe_passes = 0
          setmetatable(recipes, {
            __pairs = function(value)
              recipe_passes = recipe_passes + 1
              return next, value, nil
            end,
          })
          local result = extension.extend({gear, furnace, foreign}, values(10, 20, 10), {
            raw = raw_with_recipes(recipes), mods = {},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 2 and result.families == 2)
          assert(recipe_passes == 1)
          assert(result.work.recipes == 102 and result.work.products == 102 and result.work.matches == 2)
          assert(effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.50000")
        ''')

    def test_no_eligible_generated_family_does_not_enumerate_recipes(self):
        self.lua.execute(r'''
          local attempted = false
          local recipes = setmetatable({}, {
            __pairs = function()
              attempted = true
              error("no eligible family must skip collection")
            end,
          })
          package.loaded["compatibility.product_bindings"] = nil
          package.loaded["compatibility.product_targets"] = nil
          package.preload["compatibility.product_bindings"] = function()
            error("no eligible family must not import bindings")
          end
          package.preload["compatibility.product_targets"] = function()
            error("no eligible family must not import collector")
          end
          local foreign = {name = "foreign-productivity", effects = {productivity("foreign", .5)}}
          local result = extension.extend({foreign}, values(10, 20, 10), {
            raw = raw_with_recipes(recipes), mods = {['space-age'] = '2.1.23'},
          })
          assert_result_shape(result)
          assert(result.extended_effects == 0 and result.families == 0)
          assert(not attempted and effect_rows(foreign.effects) == "change-recipe-productivity:foreign:0.50000")
          assert(result.work.recipes == 0 and result.work.products == 0 and result.work.matches == 0)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ProductTargetExtensionTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)