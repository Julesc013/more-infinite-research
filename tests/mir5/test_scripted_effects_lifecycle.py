"""Focused Lua 5.2 lifecycle controls for MIR5's Space Age scripted effects."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ScriptedEffectsLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          function active_defaults()
            mods = {['space-age'] = '2.1.23'}
            package.loaded["research.settings"] = nil
            package.loaded["research.settings.space_age_scripted"] = nil
            local config = require("research.settings")
            local startup = {}
            for _, spec in ipairs(config.prototypes()) do startup[spec.name] = {value = spec.default_value} end
            return startup
          end

          function boot(startup, saved, world)
            mods = {['space-age'] = '2.1.23'}
            settings = {startup = startup or active_defaults()}
            storage, game, helpers, log = saved or {}, world, nil, nil
            package.loaded["runtime.configuration"] = nil
            package.loaded["runtime.scripted_effects"] = nil
            package.loaded["runtime.agriculture"] = nil
            package.loaded["runtime.spoilage"] = nil
            return require("runtime.scripted_effects")
          end
        ''')

    def test_imports_historical_buckets_and_uses_named_event_paths(self):
        self.lua.execute(r'''
          local agriculture = "recipe-prod-research_agricultural_growth_speed-1"
          local spoilage = "recipe-prod-research_spoilage_preservation-1"
          local alpha = {valid = true, name = "alpha", technologies = {
            [agriculture] = {level = 3}, [spoilage] = {level = 3}
          }}
          local saved = {mir = {
            historical_other = "keep",
            agricultural_growth_speed = {
              force_multipliers = {old = {level = 9, multiplier = 9}}, preserved = "agriculture"
            },
            spoilage_preservation = {
              baseline = 2, effective_level = 2, applied_multiplier = 1.0201,
              last_applied_value = 2.0402, preserved = "spoilage"
            }
          }}
          local world = {tick = 100, forces = {alpha = alpha},
            difficulty_settings = {spoil_time_modifier = 2.0402}}
          local runtime = boot(nil, saved, world)
          runtime.on_init()
          assert(storage.mir == saved.mir and storage.mir.historical_other == "keep")
          local agricultural_state = storage.mir.agricultural_growth_speed
          assert(agricultural_state.preserved == "agriculture"
            and agricultural_state.force_multipliers.alpha.level == 2
            and math.abs(agricultural_state.force_multipliers.alpha.multiplier - 1.0201) < .0000001)
          local spoilage_state = storage.mir.spoilage_preservation
          assert(spoilage_state.preserved == "spoilage" and spoilage_state.effective_level == 2
            and math.abs(world.difficulty_settings.spoil_time_modifier - 2.0402) < .0000001)

          alpha.technologies[agriculture].level = 2
          alpha.technologies[spoilage].level = 2
          runtime.on_research_reversed({research = {name = agriculture}})
          runtime.on_research_reversed({research = {name = spoilage}})
          assert(agricultural_state.force_multipliers.alpha.level == 1)
          assert(spoilage_state.effective_level == 1
            and math.abs(world.difficulty_settings.spoil_time_modifier - 2.02) < .0000001)

          local plant = {valid = true, force = alpha, tick_grown = 200}
          runtime.on_tower_planted_seed({tower = {valid = true, force = alpha}, plant = plant, tick = 100})
          assert(plant.tick_grown == 199, "tower callback did not use the current force level")

          storage = setmetatable({}, {__index = function() error("on_load read storage") end,
            __newindex = function() error("on_load wrote storage") end})
          game = setmetatable({}, {__index = function() error("on_load read game") end})
          runtime.on_load()
        ''')

    def test_disable_restores_only_our_matching_global_write_and_keeps_foreign_write(self):
        self.lua.execute(r'''
          local startup = active_defaults()
          startup["ips-enable-research_spoilage_preservation"].value = false
          local agriculture = "recipe-prod-research_agricultural_growth_speed-1"
          local alpha = {valid = true, name = "alpha", technologies = {[agriculture] = {level = 1}}}

          local matching = {mir = {historical_other = "keep", spoilage_preservation = {
            baseline = 2, effective_level = 1, applied_multiplier = 1.01, last_applied_value = 2.02
          }}}
          local world = {forces = {alpha = alpha}, difficulty_settings = {spoil_time_modifier = 2.02}}
          local runtime = boot(startup, matching, world)
          runtime.on_configuration_changed()
          assert(world.difficulty_settings.spoil_time_modifier == 2
            and storage.mir.spoilage_preservation == nil and storage.mir.historical_other == "keep")

          local foreign = {mir = {spoilage_preservation = {
            baseline = 2, effective_level = 1, applied_multiplier = 1.01, last_applied_value = 2.02
          }}}
          local foreign_world = {forces = {alpha = alpha}, difficulty_settings = {spoil_time_modifier = 3}}
          runtime = boot(startup, foreign, foreign_world)
          runtime.on_configuration_changed()
          assert(foreign_world.difficulty_settings.spoil_time_modifier == 3
            and storage.mir.spoilage_preservation == nil)
        ''')

    def test_force_reset_merge_and_retired_source_reconcile_without_cap_callbacks(self):
        self.lua.execute(r'''
          local agriculture = "recipe-prod-research_agricultural_growth_speed-1"
          local spoilage = "recipe-prod-research_spoilage_preservation-1"
          local function force(name, level)
            return {valid = true, name = name, technologies = {
              [agriculture] = {level = level}, [spoilage] = {level = level}
            }}
          end

          local alpha = force("alpha", 4)
          local world = {forces = {alpha = alpha}, difficulty_settings = {spoil_time_modifier = 1}}
          local runtime = boot(nil, {}, world)
          runtime.on_init()
          assert(storage.mir.agricultural_growth_speed.force_multipliers.alpha.level == 3)
          assert(storage.mir.spoilage_preservation.effective_level == 3
            and math.abs(world.difficulty_settings.spoil_time_modifier - 1.030301) < .0000001)

          alpha.technologies[agriculture].level, alpha.technologies[spoilage].level = 1, 1
          runtime.on_force_reset({force = alpha})
          assert(storage.mir.agricultural_growth_speed.force_multipliers.alpha.level == 0)
          assert(storage.mir.spoilage_preservation.effective_level == 0
            and math.abs(world.difficulty_settings.spoil_time_modifier - 1) < .0000001)

          local source, destination = force("source", 4), force("destination", 1)
          world.forces = {source = source, destination = destination}
          runtime.on_force_created({force = source})
          assert(storage.mir.spoilage_preservation.effective_level == 3
            and math.abs(world.difficulty_settings.spoil_time_modifier - 1.030301) < .0000001)
          source.valid = false
          world.forces = {destination = destination}
          runtime.on_forces_merged({source_index = 41, destination = destination})
          assert(storage.mir.agricultural_growth_speed.force_multipliers.source == nil
            and storage.mir.agricultural_growth_speed.force_multipliers.destination.level == 0)
          assert(storage.mir.spoilage_preservation.effective_level == 0
            and math.abs(world.difficulty_settings.spoil_time_modifier - 1) < .0000001)

          -- Factorio has no on_force_deleted event. The documented merge
          -- event arrives after source invalidation; with no remaining direct
          -- technology it must restore and discard only MIR's spoilage state.
          destination.technologies = {}
          runtime.on_forces_merged({source_index = 41, destination = destination})
          assert(storage.mir.spoilage_preservation == nil
            and world.difficulty_settings.spoil_time_modifier == 1)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(ScriptedEffectsLifecycleTests))
    sys.exit(0 if result.wasSuccessful() else 1)
