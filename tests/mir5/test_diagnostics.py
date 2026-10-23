"""Focused host controls for retained bounded MIR5 diagnostics."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"


class DiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          function product(name)
            return {type = "item", name = name, amount = 1}
          end

          function generated_gear()
            return {
              name = "recipe-prod-research_gears-1", enabled = true,
              effects = {{type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = .1}}
            }
          end

          function run_product_diagnostics(options)
            local lines, gear = {}, generated_gear()
            local result = require("research.product_target_extension").extend({gear}, {
              effect_percent = 10, options = options,
            }, {
              raw = {recipe = {
                ["modded-gear-producer"] = {ingredients = {}, results = {product("iron-gear-wheel")}}
              }, technology = {}},
              mods = {}, log = function(line) lines[#lines + 1] = line end
            })
            return lines, result, gear
          end

          function active_defaults()
            mods = {['space-age'] = '2.1.23'}
            package.loaded["research.settings"] = nil
            local config = require("research.settings")
            local startup = {}
            for _, spec in ipairs(config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
            return startup
          end

          function boot_scripted_effects(startup, world, messages)
            mods = {['space-age'] = '2.1.23'}
            settings, storage, game, helpers = {startup = startup}, {}, world, nil
            log = function(line) messages[#messages + 1] = line end
            package.loaded["runtime.configuration"] = nil
            package.loaded["runtime.scripted_effects"] = nil
            package.loaded["runtime.agriculture"] = nil
            package.loaded["runtime.spoilage"] = nil
            return require("runtime.scripted_effects")
          end
        ''')

    def test_collector_report_is_ordered_and_preview_is_a_bounded_disposition(self):
        self.lua.execute(r'''
          local options = {
            ["mir-debug-recipe-matches"] = true,
            ["mir-automatic-productivity-action"] = "preview",
          }
          local first, result, gear = run_product_diagnostics(options)
          local second = run_product_diagnostics(options)
          assert(result.extended_effects == 1 and result.families == 1 and #result.matches == 1)
          assert(gear.effects[2].recipe == "modded-gear-producer")
          assert(#first == 6 and #second == 6)
          for index = 1, #first do assert(first[index] == second[index]) end
          assert(first[1] == "[more-infinite-research] automatic-productivity preview: no automatic research identities; structural-fallback bindings withheld")
          assert(first[2] == "[more-infinite-research] recipe-targets report start")
          assert(first[3]:find("structural%-fallbacks=withheld action=preview selected%-families=1", 1) ~= nil)
          assert(first[4] == "[more-infinite-research] recipe-targets work recipes=1 products=1 ingredients=0 matches=1 modules=0")
          assert(first[5] == "[more-infinite-research] recipe-target match family=research_gears recipe=modded-gear-producer product=item:iron-gear-wheel weight=1 disposition=added")
          assert(first[6] == "[more-infinite-research] recipe-targets report end")

          local disabled, disabled_result = run_product_diagnostics({["mir-automatic-productivity-action"] = "apply"})
          assert(#disabled == 0 and disabled_result.matches == nil,
            "disabled recipe diagnostics emitted or retained detailed matches")

          local preview_only, preview_result = run_product_diagnostics({["mir-automatic-productivity-action"] = "preview"})
          assert(#preview_only == 1 and preview_only[1] == first[1] and preview_result.matches == nil,
            "preview must report its bounded non-emission without collector diagnostics")
        ''')

    def test_empty_catalogue_debug_report_does_not_require_matches_or_world_enumeration(self):
        self.lua.execute(r'''
          local lines = {}
          local raw = setmetatable({}, {__index = function() error("empty catalogue inspected world") end})
          local report = require("research.product_target_extension").extend({}, {
            options = {["mir-debug-recipe-matches"] = true},
          }, {raw = raw, mods = {}, log = function(line) lines[#lines + 1] = line end})
          assert(report.selected_families == 0 and report.matches == nil)
          assert(#lines == 4 and lines[2]:find("selected%-families=0 rules=0"))
          assert(lines[4] == "[more-infinite-research] recipe-targets report end")
        ''')

    def test_scripted_effect_logs_use_resolved_setting_and_leave_on_load_read_only(self):
        self.lua.execute(r'''
          local agriculture = "recipe-prod-research_agricultural_growth_speed-1"
          local spoilage = "recipe-prod-research_spoilage_preservation-1"
          local function world()
            local alpha = {valid = true, name = "alpha", technologies = {
              [agriculture] = {level = 3}, [spoilage] = {level = 3}
            }}
            return {tick = 100, forces = {alpha = alpha}, difficulty_settings = {spoil_time_modifier = 1}}, alpha
          end

          local startup, messages = active_defaults(), {}
          startup["mir-debug-scripted-effects"].value = true
          local native, alpha = world()
          local runtime = boot_scripted_effects(startup, native, messages)
          runtime.on_init()
          assert(messages[1] == "[more-infinite-research] scripted-effects agriculture event=init active=true refreshed=true")
          assert(messages[2] == "[more-infinite-research] scripted-effects spoilage event=init active=true reason=applied restored=false level=2 ambiguous=false")
          local plant = {valid = true, force = alpha, tick_grown = 200}
          runtime.on_tower_planted_seed({tower = {valid = true, force = alpha}, plant = plant, tick = 100})
          assert(#messages == 3 and messages[3]:find("agriculture event=tower%-planted%-seed applied=true", 1) ~= nil)

          storage = setmetatable({}, {__index = function() error("on_load read storage") end,
            __newindex = function() error("on_load wrote storage") end})
          game = setmetatable({}, {__index = function() error("on_load read game") end})
          runtime.on_load()
          assert(#messages == 3, "on_load produced a diagnostic or accessed runtime state")

          local quiet_startup, quiet_messages = active_defaults(), {}
          local quiet_world = world()
          local quiet = boot_scripted_effects(quiet_startup, quiet_world, quiet_messages)
          quiet.on_init()
          assert(#quiet_messages == 0, "disabled scripted-effect diagnostics emitted a log")
        ''')

    def test_disabled_scripted_diagnostics_never_format_runtime_facts(self):
        self.lua.execute(r'''
          local trap = setmetatable({}, {__tostring = function()
            error("disabled diagnostics formatted runtime facts")
          end})
          storage, game, log = {}, {}, function() error("disabled diagnostics logged") end
          package.loaded["runtime.scripted_effects"] = nil
          package.loaded["runtime.configuration"] = nil
          package.loaded["runtime.agriculture"] = nil
          package.loaded["runtime.spoilage"] = nil
          package.preload["runtime.configuration"] = function()
            return {agricultural_growth_speed = {enabled = true, effect_percent = 1},
              spoilage_preservation = {enabled = true, effect_percent = 1},
              options = {["mir-debug-scripted-effects"] = false}}
          end
          package.preload["runtime.agriculture"] = function()
            return {refresh = function() return {}, {active = trap, refreshed = trap} end}
          end
          package.preload["runtime.spoilage"] = function()
            return {reconcile = function() return {}, {active = trap, effective_level = trap,
              restored = trap, external_write_ambiguous = trap} end}
          end
          local runtime = require("runtime.scripted_effects")
          runtime.on_init()
          package.preload["runtime.configuration"] = nil
          package.preload["runtime.agriculture"] = nil
          package.preload["runtime.spoilage"] = nil
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(DiagnosticsTests))
    sys.exit(0 if result.wasSuccessful() else 1)
