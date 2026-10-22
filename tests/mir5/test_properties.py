"""Deterministic MIR 5 Generator/API host properties, not native evidence.

The mutation controls execute altered source strings in isolated Lua 5.2
states.  They never edit the player source and their rejection predicates are
based only on submitted data and observable publication, not error wording.
"""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
GENERATOR_SOURCE = (ROOT / "source/mir5/research/generator.lua").read_text(encoding="utf-8")
DATA_API_SOURCE = (ROOT / "source/mir5/api/v1/data.lua").read_text(encoding="utf-8")


class PropertyTests(unittest.TestCase):
    """Small fixed families make the intended relation inspectable."""

    def _generator_lua(self, source=GENERATOR_SOURCE):
        lua = LuaRuntime(unpack_returned_tuples=True)
        generator = lua.execute(source)
        lua.globals().generator = generator
        lua.execute('''
          function property_world()
            local raw = {
              technology = {automation = {}},
              tool = {["automation-science-pack"] = {}},
              recipe = {
                ["iron-gear-wheel"] = {}, ["copper-cable"] = {}, ["steel-plate"] = {}
              }
            }
            local stage = {raw = raw, writes = 0}
            function stage:extend(prototypes)
              self.writes = self.writes + 1
              self.emitted = prototypes
              for _, prototype in ipairs(prototypes) do
                self.raw[prototype.type] = self.raw[prototype.type] or {}
                self.raw[prototype.type][prototype.name] = prototype
              end
            end
            return stage
          end

          function property_definition(name, prerequisites, recipe)
            return {
              type = "technology", name = name, prerequisites = prerequisites or {"automation"},
              unit = {count = 10, ingredients = {{"automation-science-pack", 1}}, time = 15},
              effects = {{type = "unlock-recipe", recipe = recipe or "iron-gear-wheel"}}
            }
          end

          function property_family(prefix, count)
            local family = {}
            for index = 1, count do
              local prerequisites = {}
              if index < count then prerequisites = {prefix .. "-" .. (index + 1)} end
              family[index] = property_definition(prefix .. "-" .. index, prerequisites)
            end
            return family
          end

          function family_signature(stage)
            local parts = {tostring(stage.writes), tostring(#stage.emitted)}
            for index, prototype in ipairs(stage.emitted) do
              parts[#parts + 1] = prototype.name
              parts[#parts + 1] = table.concat(prototype.prerequisites, ",")
              parts[#parts + 1] = prototype.unit.ingredients[1][1]
              parts[#parts + 1] = prototype.effects[1].recipe
            end
            return table.concat(parts, "|")
          end

          function family_oracle(stage, prefix, count)
            assert(stage.writes == 1, "a valid family must publish exactly once")
            assert(#stage.emitted == count, "output size must equal family size")
            for index = 1, count do
              local prototype = stage.emitted[index]
              assert(prototype.name == prefix .. "-" .. index, "ordered name changed")
              if index < count then
                assert(#prototype.prerequisites == 1
                  and prototype.prerequisites[1] == prefix .. "-" .. (index + 1), "forward edge changed")
              else
                assert(#prototype.prerequisites == 0, "terminal family member changed")
              end
              assert(prototype.unit.ingredients[1][1] == "automation-science-pack"
                and prototype.effects[1].recipe == "iron-gear-wheel", "unrelated native fields changed")
            end
          end
        ''')
        return lua

    def _api_lua(self):
        lua = self._generator_lua()
        lua.execute('''
          package.preload["__more-infinite-research__/research/generator"] = function()
            return generator
          end
        ''')
        api = lua.execute(DATA_API_SOURCE)
        lua.globals().api = api
        return lua

    def _rejected_before_write(self, source, scenario):
        lua = self._generator_lua(source)
        ok, writes = lua.execute(scenario)
        return not ok and writes == 0

    def _mutate(self, old, new):
        self.assertEqual(GENERATOR_SOURCE.count(old), 1, "mutant target drifted from actual source")
        return GENERATOR_SOURCE.replace(old, new, 1)

    def test_generator_family_growth_repeatability_and_renaming(self):
        lua = self._generator_lua()
        lua.execute('''
          for _, count in ipairs({1, 2, 5, 8}) do
            local prefix = "property-family-" .. count
            local first, second = property_world(), property_world()
            generator.install(property_family(prefix, count), first)
            generator.install(property_family(prefix, count), second)
            family_oracle(first, prefix, count)
            family_oracle(second, prefix, count)
            assert(family_signature(first) == family_signature(second), "equal ordered input was not repeatable")

            local renamed_prefix = "renamed-family-" .. count
            local renamed = property_world()
            generator.install(property_family(renamed_prefix, count), renamed)
            family_oracle(renamed, renamed_prefix, count)
          end
        ''')

    def test_public_api_family_and_productivity_are_ordered_and_detached(self):
        lua = self._api_lua()
        lua.execute('''
          for _, count in ipairs({1, 3, 7}) do
            data = property_world()
            local prefix = "api-property-family-" .. count
            local input = property_family(prefix, count)
            local names = api.add_technologies(input)
            family_oracle(data, prefix, count)
            assert(#names == count, "API result size must equal input size")
            for index = 1, count do assert(names[index] == prefix .. "-" .. index, "API order changed") end
            input[1].unit.ingredients[1][2] = 99
            assert(data.emitted[1].unit.ingredients[1][2] == 1, "API output aliases caller input")
          end

          data = property_world()
          local submitted = property_definition("api-property-productivity", {})
          submitted.effects = {{type = "unlock-recipe", recipe = "steel-plate"}}
          assert(api.add_productivity(submitted, {"iron-gear-wheel", "copper-cable"}, .02)
            == "api-property-productivity")
          local emitted = data.raw.technology["api-property-productivity"]
          assert(#submitted.effects == 1 and #emitted.effects == 3, "productivity append changed input")
          assert(emitted.effects[1].recipe == "steel-plate"
            and emitted.effects[2].recipe == "iron-gear-wheel"
            and emitted.effects[3].recipe == "copper-cable", "productivity recipe order changed")
        ''')

    def test_public_api_uses_bounded_lookups_when_unrelated_prototypes_grow(self):
        lua = self._api_lua()
        lua.execute('''
          data = property_world()
          for index = 1, 512 do data.raw.recipe["unrelated-recipe-" .. index] = {} end
          local poison_pairs = function() error("whole prototype collection traversal") end
          setmetatable(data.raw.recipe, {__pairs = poison_pairs})
          setmetatable(data.raw.technology, {__pairs = poison_pairs})
          data.raw.fluid = setmetatable({}, {__pairs = poison_pairs})
          assert(api.add_technology(property_definition("api-bounded-lookup")) == "api-bounded-lookup")
          assert(data.writes == 1 and data.raw.technology["api-bounded-lookup"],
            "unrelated prototype growth changed publication")
        ''')

    def test_duplicate_guard_mutation_is_killed_by_identity_oracle(self):
        scenario = '''
          local first = property_definition("duplicate-property-id", {})
          local second = property_definition("duplicate-property-id", {})
          local stage = property_world()
          local ok = pcall(generator.install, {first, second}, stage)
          return ok, stage.writes
        '''
        duplicate_guard = 'if names[name] or (raw.technology and raw.technology[name]) then reject("duplicate technology " .. name) end'
        mutant = self._mutate(duplicate_guard, 'if false then reject("duplicate technology " .. name) end')
        self.assertTrue(self._rejected_before_write(GENERATOR_SOURCE, scenario))
        self.assertFalse(self._rejected_before_write(mutant, scenario),
            "identity oracle did not kill the duplicate-guard mutant")

    def test_cycle_guard_mutation_is_killed_by_graph_oracle(self):
        scenario = '''
          local first = property_definition("cycle-property-a", {"cycle-property-b"})
          local second = property_definition("cycle-property-b", {"cycle-property-a"})
          local stage = property_world()
          local ok = pcall(generator.install, {first, second}, stage)
          return ok, stage.writes
        '''
        cycle_guard = 'if #queue ~= count then reject("local prerequisite cycle") end'
        mutant = self._mutate(cycle_guard, 'if false then reject("local prerequisite cycle") end')
        self.assertTrue(self._rejected_before_write(GENERATOR_SOURCE, scenario))
        self.assertFalse(self._rejected_before_write(mutant, scenario),
            "graph oracle did not kill the local-cycle mutant")

    def test_recipe_target_guard_mutation_is_killed_by_reference_oracle(self):
        scenario = '''
          local invalid = property_definition("missing-recipe-property", {}, "missing-recipe")
          local stage = property_world()
          local ok = pcall(generator.install, {invalid}, stage)
          return ok, stage.writes
        '''
        recipe_guard = 'if type(effect.recipe) ~= "string" or not (raw.recipe and raw.recipe[effect.recipe]) then'
        mutant = self._mutate(recipe_guard, 'if false then')
        self.assertTrue(self._rejected_before_write(GENERATOR_SOURCE, scenario))
        self.assertFalse(self._rejected_before_write(mutant, scenario),
            "reference oracle did not kill the missing-recipe mutant")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(PropertyTests))
    sys.exit(0 if result.wasSuccessful() else 1)
