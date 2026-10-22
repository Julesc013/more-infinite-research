"""Pure Lua 5.2 controls for the MIR 5 data API, not native Factorio evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
API_MODULE = "__more-infinite-research__.api.v1.data"


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          package.preload["__more-infinite-research__.api.v1.data"] = function()
            return assert(loadfile(player_root .. "/api/v1/data.lua"))()
          end
          api = require("__more-infinite-research__.api.v1.data")

          function world()
            local raw = {
              technology = {automation = {}, electronics = {}},
              tool = { ["automation-science-pack"] = {} },
              recipe = {["iron-gear-wheel"] = {}, ["copper-cable"] = {}}
            }
            local stage = {raw = raw, writes = 0}
            function stage:extend(prototypes)
              self.writes = self.writes + 1
              for _, prototype in ipairs(prototypes) do
                self.raw[prototype.type] = self.raw[prototype.type] or {}
                self.raw[prototype.type][prototype.name] = prototype
              end
            end
            return stage
          end

          function definition(name, prerequisites)
            return {
              type = "technology", name = name, prerequisites = prerequisites or {"automation"},
              unit = {count = 10, ingredients = {{"automation-science-pack", 1}}, time = 15},
              effects = {}
            }
          end

          function refused(callback, code)
            local writes = data.writes
            local ok, message = pcall(callback)
            assert(not ok, "invalid API input was accepted")
            assert(tostring(message):find("MIR_API:" .. code, 1, true), tostring(message))
            assert(data.writes == writes, "rejected API input wrote prototypes")
          end
        ''')

    def fresh(self):
        self.lua.execute("data = world(); mods = {[\"more-infinite-research\"] = \"5.0.21000\"}")

    def test_version_and_capabilities_are_detached_actual_metadata(self):
        self.fresh()
        self.lua.execute('''
          local version = api.get_version()
          assert(version.major == 1 and version.minor == 0 and version.product == "5.0.21000")
          version.major = 99
          assert(api.get_version().major == 1)
          local capabilities = api.get_capabilities()
          assert(capabilities.technology_creation and capabilities.technology_family
            and capabilities.recipe_productivity and not capabilities.research_query)
          capabilities.recipe_productivity = false
          assert(api.get_capabilities().recipe_productivity)
        ''')

    def test_single_creation_is_immediate_and_detached(self):
        self.fresh()
        self.lua.execute('''
          local submitted = definition("mir-api-single-1")
          assert(api.add_technology(submitted) == "mir-api-single-1")
          local emitted = data.raw.technology[submitted.name]
          assert(data.writes == 1 and emitted and emitted ~= submitted)
          submitted.unit.ingredients[1][2] = 99
          emitted.unit.ingredients[1][2] = 2
          assert(emitted.unit.ingredients[1][2] == 2 and submitted.unit.ingredients[1][2] == 99)
        ''')

    def test_family_keeps_order_and_permits_local_forward_references(self):
        self.fresh()
        self.lua.execute('''
          local first = definition("mir-api-family-first", {"mir-api-family-second"})
          local second = definition("mir-api-family-second")
          local names = api.add_technologies({first, second})
          assert(data.writes == 1 and names[1] == first.name and names[2] == second.name)
          assert(data.raw.technology[first.name].prerequisites[1] == second.name)
        ''')

    def test_productivity_appends_distinct_native_effects_without_input_aliasing(self):
        self.fresh()
        self.lua.execute('''
          local submitted = definition("mir-api-productivity-1")
          submitted.effects = {{type = "unlock-recipe", recipe = "iron-gear-wheel"}}
          assert(api.add_productivity(submitted, {"iron-gear-wheel", "copper-cable"}, .02) == submitted.name)
          local emitted = data.raw.technology[submitted.name]
          assert(#submitted.effects == 1 and #emitted.effects == 3)
          assert(emitted.effects[2].type == "change-recipe-productivity"
            and emitted.effects[2].recipe == "iron-gear-wheel" and emitted.effects[2].change == .02)
          assert(emitted.effects[3].recipe == "copper-cable" and emitted.effects[3].change == .02)
        ''')

    def test_invalid_cycles_metatables_and_sparse_inputs_fail_before_writes(self):
        self.fresh()
        self.lua.execute('''
          local cyclic = definition("mir-api-cycle-1"); cyclic.unit.self = cyclic.unit
          refused(function() api.add_technology(cyclic) end, "invalid_definition")
          local decorated = setmetatable(definition("mir-api-metatable-1"), {})
          refused(function() api.add_technology(decorated) end, "invalid_definition")
          local executable = definition("mir-api-function-1"); executable.localised_name = function() end
          refused(function() api.add_technology(executable) end, "invalid_definition")
          refused(function() api.add_technologies({[1] = definition("mir-api-sparse-a"), [3] = definition("mir-api-sparse-b")}) end,
            "invalid_definition")
        ''')

    def test_scalar_wide_and_deep_inputs_stop_at_the_boundary_budget(self):
        self.fresh()
        self.lua.execute('''
          local wide = definition("mir-api-wide-1"); wide.localised_description = {}
          for index = 1, 600 do wide.localised_description[index] = "scalar" end
          refused(function() api.add_technology(wide) end, "invalid_definition")
          local deep = definition("mir-api-deep-1"); deep.localised_description = {}
          local cursor = deep.localised_description
          for index = 1, 20 do cursor.child = {}; cursor = cursor.child end
          refused(function() api.add_technology(deep) end, "invalid_definition")
        ''')

    def test_duplicate_and_missing_productivity_targets_fail_without_writes(self):
        self.fresh()
        self.lua.execute('''
          local duplicate = definition("mir-api-duplicate-1")
          api.add_technology(duplicate)
          refused(function() api.add_technology(duplicate) end, "duplicate_identity")
          local existing = definition("mir-api-existing-productivity-1")
          existing.effects = {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = .01}}
          refused(function() api.add_productivity(existing, {"iron-gear-wheel"}, .02) end, "duplicate_identity")
          refused(function() api.add_productivity(definition("mir-api-duplicate-recipes-1"),
            {"iron-gear-wheel", "iron-gear-wheel"}, .02) end, "duplicate_identity")
          refused(function() api.add_productivity(definition("mir-api-missing-recipe-1"),
            {"missing-recipe"}, .02) end, "missing_target")
        ''')

    def test_native_publication_error_is_rethrown_with_its_context(self):
        self.fresh()
        self.lua.execute('''
          data.extend = function() error("native schema rejection") end
          local ok, message = pcall(api.add_technology, definition("mir-api-native-error-1"))
          assert(not ok and tostring(message):find("MIR_API:invalid_definition", 1, true))
          assert(tostring(message):find("native schema rejection", 1, true))
        ''')

    def test_independent_required_and_late_optional_consumers(self):
        self.fresh()
        alpha = ROOT / "tests/mir5/fixtures/api-alpha/data.lua"
        beta = ROOT / "tests/mir5/fixtures/api-beta/data-final-fixes.lua"
        self.lua.globals().alpha_fixture = alpha.as_posix()
        self.lua.globals().beta_fixture = beta.as_posix()
        self.lua.execute('''
          assert(loadfile(alpha_fixture))()
          assert(data.raw.technology["mir-api-fixture-alpha-1"])
          assert(data.raw.technology["mir-api-fixture-alpha-2"])
          assert(loadfile(beta_fixture))()
          local beta = data.raw.technology["mir-api-fixture-beta-cable-1"]
          assert(data.writes == 2 and beta and #beta.effects == 1)
          assert(beta.effects[1].type == "change-recipe-productivity"
            and beta.effects[1].recipe == "copper-cable")
        ''')

    def test_optional_consumer_handles_mir_absence_before_importing(self):
        self.lua.execute("data = world(); mods = {}; package.loaded[\"__more-infinite-research__.api.v1.data\"] = nil")
        beta = ROOT / "tests/mir5/fixtures/api-beta/data-final-fixes.lua"
        self.lua.globals().beta_fixture = beta.as_posix()
        self.lua.execute('''
          assert(loadfile(beta_fixture))()
          assert(data.writes == 0 and package.loaded["__more-infinite-research__.api.v1.data"] == nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ApiTests))
    sys.exit(0 if result.wasSuccessful() else 1)
