"""Pure Lua 5.2 controls for the MIR 5 data API, not native Factorio evidence."""
import argparse
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
API_MODULE = "__more-infinite-research__.api.v1.data"


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          package.preload["__more-infinite-research__/research/generator"] = function()
            return require("research.generator")
          end
          package.preload["__more-infinite-research__/platform/target"] = function()
            return assert(loadfile(player_root .. "/platform/target.lua"))()
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

    def fresh_f200(self):
        self.lua.execute('''
          package.loaded["platform.target"] = {
            id = "f200", factorio_version = "2.0", minimum_base = "2.0.77",
            distribution_version = "5.0.20000", reduced = false,
            research_levels = true, recipe_productivity = true,
            recipe_probability = "independent_probability",
            productivity_ignores_stats = true, receiver_limits = true,
            cargo_research = false
          }
          package.loaded["__more-infinite-research__/platform/target"] = package.loaded["platform.target"]
          package.loaded["__more-infinite-research__.api.v1.data"] = nil
          api = require("__more-infinite-research__.api.v1.data")
          data = world()
          mods = {["more-infinite-research"] = "5.0.20000"}
        ''')

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

    def test_api_presentation_is_the_packaged_owned_288px_thumbnail(self):
        thumbnail = (ROOT / "source/thumbnail.png").read_bytes()
        self.assertEqual(thumbnail[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(thumbnail[12:16], b"IHDR")
        self.assertEqual(struct.unpack(">II", thumbnail[16:24]), (288, 288))

    def test_single_creation_is_immediate_and_detached(self):
        self.fresh()
        self.lua.execute('''
          local submitted = definition("mir-api-single-1")
          assert(api.add_technology(submitted) == "mir-api-single-1")
          local emitted = data.raw.technology[submitted.name]
          assert(data.writes == 1 and emitted and emitted ~= submitted)
          assert(emitted.icon == "__more-infinite-research__/thumbnail.png" and emitted.icon_size == 288)
          assert(submitted.icon == nil and submitted.icon_size == nil)
          submitted.unit.ingredients[1][2] = 99
          emitted.unit.ingredients[1][2] = 2
          assert(emitted.unit.ingredients[1][2] == 2 and submitted.unit.ingredients[1][2] == 99)
        ''')

    def test_external_consumer_target_namespace_cannot_replace_mir_capabilities(self):
        self.fresh()
        self.lua.execute('''
          for _, consumer in ipairs({"alpha", "beta"}) do
            local private_target = {distribution_version=consumer .. "-private",
              recipe_productivity=false, cargo_research=false}
            package.loaded["platform.target"] = private_target
            package.loaded["__more-infinite-research__/platform/target"] = nil
            package.loaded["__more-infinite-research__.api.v1.data"] = nil
            local external_api = require("__more-infinite-research__.api.v1.data")
            assert(external_api.get_version().product == "5.0.21000",
              "external API consumed " .. consumer .. "'s private target metadata")
            assert(external_api.get_capabilities().recipe_productivity)
            local name = "mir-api-namespace-" .. consumer
            assert(external_api.add_productivity(definition(name), {"iron-gear-wheel"}, .01) == name)
            assert(data.raw.technology[name].effects[1].change == .01)
            assert(package.loaded["platform.target"] == private_target
              and private_target.recipe_productivity == false,
              "MIR must neither load nor rewrite the consumer's private module")
          end
          assert(data.writes == 2)
        ''')

    def test_native_namespace_collision_fixtures_keep_private_targets_and_publish_distinct_effects(self):
        fixture_root = ROOT / "tests/fixtures"
        profile = json.loads(
            (ROOT / "tests/profiles/api-namespace-collision-f210-2123.json").read_text(encoding="utf-8")
        )
        self.assertEqual(profile["kind"], "mir5-api-namespace-collision-f210-native-selection")
        self.assertEqual((profile["target"], profile["factorio_line"], profile["engine"]["version"]),
                         ("f210", "2.1", "2.1.23"))
        self.assertEqual(profile["settings_mode"], "Defaults")
        self.assertEqual(
            [(row["name"], row["version"], row["enabled"]) for row in profile["mods"]],
            [
                ("base", "2.1.23", True),
                ("more-infinite-research", "5.0.21000", True),
                ("mir-fixture-mir5-api-namespace-alpha", "0.1.0", True),
                ("mir-fixture-mir5-api-namespace-beta", "0.1.0", True),
                ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ],
        )

        alpha_root = fixture_root / "api-namespace-alpha"
        beta_root = fixture_root / "api-namespace-beta"
        for root, consumer in ((alpha_root, "alpha"), (beta_root, "beta")):
            info = json.loads((root / "info.json").read_text(encoding="utf-8"))
            self.assertEqual(info["name"], f"mir-fixture-mir5-api-namespace-{consumer}")
            self.assertEqual(info["factorio_version"], "2.1")
            self.assertEqual(info["dependencies"], [
                "base >= 2.1.23", "more-infinite-research = 5.0.21000",
            ])

        self.lua.globals().namespace_alpha_data = (alpha_root / "data.lua").as_posix()
        self.lua.globals().namespace_alpha_target = (alpha_root / "platform/target.lua").as_posix()
        self.lua.globals().namespace_alpha_control = (alpha_root / "control.lua").as_posix()
        self.lua.globals().namespace_beta_data = (beta_root / "data-final-fixes.lua").as_posix()
        self.lua.globals().namespace_beta_target = (beta_root / "platform/target.lua").as_posix()
        self.lua.globals().namespace_beta_control = (beta_root / "control.lua").as_posix()
        legacy_source = (ROOT / "source/api/v1/data.lua").read_text(encoding="utf-8")
        old_import = 'local target = require("__more-infinite-research__/platform/target")'
        self.assertIn(old_import, legacy_source)
        self.lua.globals().legacy_namespace_api_source = legacy_source.replace(
            old_import, 'local target = require("platform.target")', 1
        )
        self.lua.execute(r'''
          function namespace_target(path)
            return assert(loadfile(path))()
          end

          function run_namespace_data(path, private_target, public_api)
            local environment = {
              data = data,
              require = function(name)
                if name == "platform.target" then return private_target end
                if name == "__more-infinite-research__.api.v1.data" then return public_api end
                error("namespace fixture imported unexpected module " .. tostring(name))
              end
            }
            setmetatable(environment, {__index = _G})
            return assert(loadfile(path, "t", environment))()
          end

          function run_namespace_control(path, private_target, technology_name, recipe_name, change)
            local callbacks, reports, messages = {}, {}, {}
            local environment = {
              require = function(name)
                assert(name == "platform.target")
                return private_target
              end,
              script = {on_init = function(callback) callbacks.init = callback end},
              game = {forces = {player = {technologies = {
                [technology_name] = {prototype = {effects = {{
                  type = "change-recipe-productivity", recipe = recipe_name, change = change
                }}}}
              }}}},
              helpers = {table_to_json = function(row) reports[#reports + 1] = row; return "fixture-json" end},
              log = function(message) messages[#messages + 1] = message end
            }
            setmetatable(environment, {__index = _G})
            assert(loadfile(path, "t", environment))()
            local ok, message = pcall(callbacks.init)
            return ok, tostring(message), reports[1], messages[1]
          end

          function legacy_namespace_api(private_target)
            package.loaded["platform.target"] = nil
            package.preload["platform.target"] = function() return private_target end
            return assert(load(legacy_namespace_api_source, "legacy-mir-api-data"))()
          end
        ''')

        self.fresh()
        self.lua.execute(r'''
          local alpha_private = namespace_target(namespace_alpha_target)
          local beta_private = namespace_target(namespace_beta_target)
          assert(alpha_private ~= beta_private and alpha_private.owner ~= beta_private.owner)
          assert(run_namespace_data(namespace_alpha_data, alpha_private, api) == nil)
          assert(run_namespace_data(namespace_beta_data, beta_private, api) == nil)

          local alpha = assert(data.raw.technology["mir-api-namespace-alpha-gears-1"])
          local beta = assert(data.raw.technology["mir-api-namespace-beta-cable-1"])
          assert(data.writes == 2 and alpha ~= beta)
          assert(alpha.effects[1].recipe == "iron-gear-wheel" and alpha.effects[1].change == .01)
          assert(beta.effects[1].recipe == "copper-cable" and beta.effects[1].change == .02)
          assert(alpha_private.distribution_version == "private-alpha-target"
            and beta_private.distribution_version == "private-beta-target")
          assert(api.get_version().product == "5.0.21000" and api.get_capabilities().recipe_productivity)

          local ok, message, alpha_result, alpha_log = run_namespace_control(
            namespace_alpha_control, alpha_private, "mir-api-namespace-alpha-gears-1", "iron-gear-wheel", .01)
          assert(ok, message)
          assert(alpha_result.stage == "init" and alpha_result.status == "passed",
            "alpha marker does not match native runner's init consumer protocol")
          assert(alpha_result.consumer == alpha_private.owner and alpha_result.change == .01
            and alpha_log:find("MIR5_API_NAMESPACE_ALPHA", 1, true))
          ok, message, beta_result, beta_log = run_namespace_control(
            namespace_beta_control, beta_private, "mir-api-namespace-beta-cable-1", "copper-cable", .02)
          assert(ok, message)
          assert(beta_result.stage == "init" and beta_result.status == "passed",
            "beta marker does not match native runner's init consumer protocol")
          assert(beta_result.consumer == beta_private.owner and beta_result.change == .02
            and beta_log:find("MIR5_API_NAMESPACE_BETA", 1, true))

          local wrong_effect_ok, wrong_effect = run_namespace_control(
            namespace_alpha_control, alpha_private, "mir-api-namespace-alpha-gears-1", "iron-gear-wheel", .02)
          assert(not wrong_effect_ok and wrong_effect:find("native gear productivity technology differs", 1, true))
          local wrong_target = {owner = "wrong", recipe_productivity = false}
          local wrong_target_ok, wrong_target_error = run_namespace_control(
            namespace_beta_control, wrong_target, "mir-api-namespace-beta-cable-1", "copper-cable", .02)
          assert(not wrong_target_ok and wrong_target_error:find("private target identity differs", 1, true))
        ''')

        self.fresh()
        self.lua.execute(r'''
          for _, row in ipairs({
            {data = namespace_alpha_data, target = namespace_alpha_target},
            {data = namespace_beta_data, target = namespace_beta_target}
          }) do
            local private_target = namespace_target(row.target)
            local legacy = legacy_namespace_api(private_target)
            local ok, message = pcall(run_namespace_data, row.data, private_target, legacy)
            assert(not ok and tostring(message):find("public target metadata differs", 1, true), tostring(message))
            assert(data.writes == 0, "unqualified legacy import emitted a technology")
          end
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
          assert(api.add_productivity(submitted, {"iron-gear-wheel", "copper-cable"}, .02) == submitted.name)
          local emitted = data.raw.technology[submitted.name]
          assert(#submitted.effects == 0 and #emitted.effects == 2)
          assert(emitted.effects[1].type == "change-recipe-productivity"
            and emitted.effects[1].recipe == "iron-gear-wheel" and emitted.effects[1].change == .02)
          assert(emitted.effects[2].recipe == "copper-cable" and emitted.effects[2].change == .02)
          submitted.unit.ingredients[1][2] = 99
          assert(emitted.unit.ingredients[1][2] == 1)
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

    def test_admission_subset_rejects_native_schema_escapes_before_any_family_write(self):
        self.fresh()
        self.lua.execute('''
          local bad_effect = definition("mir-api-bad-effect-1")
          bad_effect.effects = {{type = "not-a-factorio-modifier"}}
          refused(function() api.add_technology(bad_effect) end, "invalid_definition")
          local bad_icon = definition("mir-api-bad-icon-1")
          bad_icon.icon = "__foreign__/graphics/not-checked.png"
          refused(function() api.add_technology(bad_icon) end, "invalid_definition")
          local formula = definition("mir-api-formula-1")
          formula.unit.count = nil
          formula.unit.count_formula = "L +"
          refused(function() api.add_technology(formula) end, "invalid_definition")
          local incomplete = definition("mir-api-incomplete-unit-1")
          incomplete.unit.time = nil
          refused(function() api.add_technology(incomplete) end, "invalid_definition")
          local sub_tick = definition("mir-api-sub-tick-1")
          sub_tick.unit.time = 1e-300
          refused(function() api.add_technology(sub_tick) end, "invalid_definition")
          local excessive_time = definition("mir-api-excessive-time-1")
          excessive_time.unit.time = 1e300
          refused(function() api.add_technology(excessive_time) end, "invalid_definition")
          local nonfinite_time = definition("mir-api-nonfinite-time-1")
          nonfinite_time.unit.time = math.huge
          refused(function() api.add_technology(nonfinite_time) end, "invalid_definition")
          local malformed_ingredient = definition("mir-api-ingredient-1")
          malformed_ingredient.unit.ingredients[1][3] = "unexpected"
          refused(function() api.add_technology(malformed_ingredient) end, "invalid_definition")
          local unsafe_modifier = definition("mir-api-modifier-1")
          unsafe_modifier.effects = {{type = "character-crafting-speed", modifier = 2}}
          refused(function() api.add_technology(unsafe_modifier) end, "invalid_definition")
          local caller_productivity = definition("mir-api-caller-productivity-1")
          caller_productivity.effects = {{type = "change-recipe-productivity",
            recipe = "iron-gear-wheel", change = .01}}
          refused(function() api.add_productivity(caller_productivity, {"copper-cable"}, .02) end,
            "invalid_definition")
          local first = definition("mir-api-family-safe-1")
          local second = definition("mir-api-family-unsafe-1")
          second.localised_name = {"bad", "native-shape"}
          refused(function() api.add_technologies({first, second}) end, "invalid_definition")
          assert(data.raw.technology[first.name] == nil,
            "a later family rejection must not publish an earlier member")
          local control_name = definition("mir-api-control-byte-1")
          control_name.name = "mir-api-control-" .. string.char(1)
          refused(function() api.add_technology(control_name) end, "invalid_definition")
          local min_time = definition("mir-api-min-time-1")
          min_time.unit.time = 1 / 60
          assert(api.add_technology(min_time) == min_time.name)
          local max_time = definition("mir-api-max-time-1")
          max_time.unit.time = 3600000
          assert(api.add_technology(max_time) == max_time.name)
        ''')

    def test_target_specific_science_item_types_and_duplicate_names_reject_before_writes(self):
        self.fresh()
        self.lua.execute('''
          -- F210 ResearchIngredient accepts ItemPrototype, including the
          -- generic item prototype that F200's older TechnologyUnit forbids.
          data.raw.item = { ["mir-api-f210-generic-item"] = {} }
          local f210_generic = definition("mir-api-f210-generic-item-1")
          f210_generic.unit.ingredients = {{"mir-api-f210-generic-item", 1}}
          assert(api.add_technology(f210_generic) == f210_generic.name)
          local f210_duplicate = definition("mir-api-f210-duplicate-ingredient-1")
          f210_duplicate.unit.ingredients = {
            {"automation-science-pack", 1}, {"automation-science-pack", 1}
          }
          refused(function() api.add_technology(f210_duplicate) end, "invalid_definition")
        ''')

        self.fresh_f200()
        self.lua.execute('''
          data.raw.item = { ["mir-api-f200-generic-item"] = {} }
          local f200_generic = definition("mir-api-f200-generic-item-1")
          f200_generic.unit.ingredients = {{"mir-api-f200-generic-item", 1}}
          refused(function() api.add_technology(f200_generic) end, "missing_target")
          local f200_duplicate = definition("mir-api-f200-duplicate-ingredient-1")
          f200_duplicate.unit.ingredients = {
            {"automation-science-pack", 1}, {"automation-science-pack", 1}
          }
          refused(function() api.add_technology(f200_duplicate) end, "invalid_definition")
          local f200_tool = definition("mir-api-f200-tool-item-1")
          assert(api.add_technology(f200_tool) == f200_tool.name)
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
          refused(function() api.add_productivity(existing, {"iron-gear-wheel"}, .02) end, "invalid_definition")
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
        alpha = ROOT / "tests/fixtures/api-alpha/data.lua"
        beta = ROOT / "tests/fixtures/api-beta/data-final-fixes.lua"
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

    def test_f200_required_alpha_and_late_optional_beta_remain_detached(self):
        self.fresh_f200()
        alpha = ROOT / "tests/fixtures/api-alpha/data.lua"
        beta = ROOT / "tests/fixtures/api-beta/data-final-fixes.lua"
        self.lua.globals().alpha_fixture = alpha.as_posix()
        self.lua.globals().beta_fixture = beta.as_posix()
        self.lua.execute('''
          assert(api.get_version().product == "5.0.20000")
          assert(api.get_capabilities().recipe_productivity == true)
          assert(loadfile(alpha_fixture))()
          assert(loadfile(beta_fixture))()
          local alpha = assert(data.raw.technology["mir-api-fixture-alpha-1"])
          local prerequisite = assert(data.raw.technology["mir-api-fixture-alpha-2"])
          local beta = assert(data.raw.technology["mir-api-fixture-beta-cable-1"])
          assert(data.writes == 2 and alpha ~= prerequisite and alpha ~= beta and prerequisite ~= beta)
          assert(#alpha.effects == 1 and alpha.effects[1].type == "character-crafting-speed"
            and alpha.effects[1].modifier == .05)
          assert(#prerequisite.effects == 0)
          assert(#beta.effects == 1 and beta.effects[1].type == "change-recipe-productivity"
            and beta.effects[1].recipe == "copper-cable" and beta.effects[1].change == .01)
          alpha.effects[1].modifier = .5
          assert(beta.effects[1].change == .01,
            "required alpha mutation must not alias the optional beta effect")
        ''')

    def test_optional_consumer_handles_mir_absence_before_importing(self):
        self.lua.execute("data = world(); mods = {}; package.loaded[\"__more-infinite-research__.api.v1.data\"] = nil")
        beta = ROOT / "tests/fixtures/api-beta/data-final-fixes.lua"
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
