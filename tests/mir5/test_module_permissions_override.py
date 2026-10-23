"""Lua 5.2 controls for the source-characterized unrestricted-module override."""

import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ModulePermissionsOverrideTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r"""
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          override = require("overrides.module_permissions")

          function assert_array(actual, expected)
            assert(#actual == #expected, "array length")
            for index, value in ipairs(expected) do
              assert(actual[index] == value, "array entry " .. tostring(index))
            end
          end
        """)

    def test_disabled_or_non_boolean_enabled_never_reads_or_enumerates_raw(self):
        self.lua.execute(r"""
          local raw = setmetatable({}, {
            __index = function(_, key) error("inactive read " .. tostring(key)) end,
            __pairs = function() error("inactive enumeration") end
          })
          local disabled = override.apply(raw, false)
          assert(not disabled.active and disabled.visited == 0)
          assert(disabled.recipes_changed == 0 and disabled.receivers_changed == 0)

          local non_boolean = override.apply(raw, 1)
          assert(not non_boolean.active and non_boolean.visited == 0)
        """)

    def test_valid_override_discovers_categories_and_preserves_foreign_fields(self):
        self.lua.execute(r"""
          local old_recipe_categories = {"narrow"}
          local old_receiver_categories = {"narrow"}
          local old_effects = {"speed"}
          local foreign_recipe = {unchanged = true}
          local foreign_receiver = {unchanged = true}
          local recipe = {
            category = "crafting", result = "widget", foreign = foreign_recipe,
            allow_speed = false, allow_productivity = false, allow_consumption = false,
            allow_pollution = false, allow_quality = false,
            allowed_module_categories = old_recipe_categories
          }
          local parameter = {parameter = true, foreign = "parameter",
            allowed_module_categories = {"never-replaced"}}
          local assembler = {
            module_slots = 2, foreign = foreign_receiver,
            allowed_effects = old_effects, allowed_module_categories = old_receiver_categories
          }
          local zero_slots = {module_slots = 0, foreign = "zero",
            allowed_effects = {"unchanged"}}
          local beacon = {module_slots = "1", foreign = "beacon"}
          local raw = {
            ["module-category"] = {quality = {}, speed = {}, zeta = {}},
            module = {custom = {category = "custom-category"}, invalid = {category = false}},
            recipe = {valid = recipe, parameter = parameter, invalid = false},
            ["assembling-machine"] = {assembler = assembler},
            furnace = {zero = zero_slots},
            beacon = {beacon = beacon},
            unrelated = setmetatable({}, {__pairs = function()
              error("whole-domain raw scan")
            end})
          }

          local facts = override.apply(raw, true)
          assert(facts.active and facts.recipes_changed == 1 and facts.receivers_changed == 2)
          assert(facts.visited == 11)
          assert_array(facts.module_categories, {"custom-category", "quality", "speed", "zeta"})
          assert(facts.receiver_counts["assembling-machine"] == 1)
          assert(facts.receiver_counts.furnace == 0 and facts.receiver_counts.beacon == 1)
          assert(facts.receiver_counts.lab == 0 and facts.receiver_counts["agricultural-tower"] == 0)

          assert(recipe.category == "crafting" and recipe.result == "widget" and recipe.foreign == foreign_recipe)
          assert(recipe.allow_speed and recipe.allow_productivity and recipe.allow_consumption)
          assert(recipe.allow_pollution and recipe.allow_quality)
          assert_array(recipe.allowed_module_categories,
            {"custom-category", "quality", "speed", "zeta"})
          assert(recipe.allowed_module_categories ~= old_recipe_categories)
          assert_array(old_recipe_categories, {"narrow"})

          assert(parameter.foreign == "parameter")
          assert_array(parameter.allowed_module_categories, {"never-replaced"})
          assert(zero_slots.foreign == "zero")
          assert_array(zero_slots.allowed_effects, {"unchanged"})

          assert(assembler.foreign == foreign_receiver and beacon.foreign == "beacon")
          assert_array(assembler.allowed_effects,
            {"speed", "productivity", "consumption", "pollution", "quality"})
          assert_array(assembler.allowed_module_categories,
            {"custom-category", "quality", "speed", "zeta"})
          assert(assembler.allowed_effects ~= old_effects)
          assert(assembler.allowed_module_categories ~= old_receiver_categories)
          assert_array(old_effects, {"speed"})
          assert_array(old_receiver_categories, {"narrow"})
        """)

    def test_absent_groups_are_active_but_have_no_work(self):
        self.lua.execute(r"""
          local facts = override.apply({recipe = {}}, true)
          assert(facts.active and facts.visited == 0)
          assert(facts.recipes_changed == 0 and facts.receivers_changed == 0)
          assert(#facts.module_categories == 0)
          assert(facts.receiver_counts["rocket-silo"] == 0)
        """)

    def test_results_are_deterministic_across_input_insertion_order(self):
        self.lua.execute(r"""
          local function raw(reverse)
            local categories, modules = {}, {}
            if reverse then
              categories.zeta, categories.alpha = {}, {}
              modules.second, modules.first = {category = "gamma"}, {category = "alpha"}
            else
              categories.alpha, categories.zeta = {}, {}
              modules.first, modules.second = {category = "alpha"}, {category = "gamma"}
            end
            return {
              ["module-category"] = categories,
              module = modules,
              recipe = {one = {foreign = "a"}},
              lab = {one = {module_slots = 1, foreign = "b"}}
            }
          end

          local left, right = raw(false), raw(true)
          local left_facts, right_facts = override.apply(left, true), override.apply(right, true)
          assert(left_facts.visited == right_facts.visited)
          assert(left_facts.recipes_changed == right_facts.recipes_changed)
          assert(left_facts.receivers_changed == right_facts.receivers_changed)
          assert_array(left_facts.module_categories, {"alpha", "gamma", "zeta"})
          assert_array(right_facts.module_categories, {"alpha", "gamma", "zeta"})
          assert_array(left.recipe.one.allowed_module_categories, right.recipe.one.allowed_module_categories)
          assert_array(left.lab.one.allowed_effects, right.lab.one.allowed_effects)
        """)

    def test_each_selected_mutation_receives_detached_arrays(self):
        self.lua.execute(r"""
          local first_recipe, second_recipe = {}, {}
          local first_receiver, second_receiver = {module_slots = 1}, {module_slots = 1}
          local raw = {
            ["module-category"] = {alpha = {}},
            recipe = {first = first_recipe, second = second_recipe},
            lab = {first = first_receiver, second = second_receiver}
          }
          local facts = override.apply(raw, true)
          assert(facts.recipes_changed == 2 and facts.receivers_changed == 2)

          first_recipe.allowed_module_categories[1] = "changed"
          first_receiver.allowed_effects[1] = "changed"
          facts.module_categories[1] = "changed"
          assert(second_recipe.allowed_module_categories[1] == "alpha")
          assert(first_receiver.allowed_module_categories[1] == "alpha")
          assert(second_receiver.allowed_effects[1] == "speed")
          assert(second_receiver.allowed_module_categories[1] == "alpha")
        """)

    def test_source_stays_standalone_and_records_published_contract(self):
        source = (ROOT / "source/mir5/overrides/module_permissions.lua").read_text(encoding="utf-8")
        self.assertIn("84bd157ad7b63b7d171fac2311bf30de70429c11", source)
        self.assertIn("dbac07646aefdb16dbc6c09a990be6b665ca1559aa99ae585c82cd1461f614fd", source)
        self.assertNotIn("require(", source)
        self.assertNotIn("Generator", source)
        self.assertNotIn("data.raw", source)
        self.assertNotIn("settings.", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ModulePermissionsOverrideTests))
    sys.exit(0 if result.wasSuccessful() else 1)
