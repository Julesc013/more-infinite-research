"""Pure Lua 5.2 host-stage parse checks for MIR 5 API consumer controls."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
RUNTIME_API = Path("C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json")


class FixtureControlHostStageTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r"""
          function parse_consumer_control(path, active_mir)
            local callbacks = {}
            local forbidden = {reads = {}, writes = {}}
            local active_mods = {base = "2.1.23"}
            if active_mir then active_mods["more-infinite-research"] = "5.0.21000" end

            local remote_probe = setmetatable({}, {
              __index = function() error("control parse accessed remote") end
            })
            local environment = {
              script = {
                active_mods = active_mods,
                on_init = function(callback) callbacks.on_init = callback end,
                on_load = function(callback) callbacks.on_load = callback end,
                on_configuration_changed = function(callback) callbacks.on_configuration_changed = callback end,
                on_event = function(event, callback)
                  callbacks.on_event = {event = event, callback = callback}
                end
              },
              defines = {events = {on_tick = 1}},
              remote = remote_probe,
              helpers = {table_to_json = function(value)
                assert(value.stage == "init" and value.case == "module-permissions"
                  and value.status == "passed")
                return "{}"
              end},
              log = function() end,
              require = function() error("control parse imported a module") end
            }
            environment._G = environment
            setmetatable(environment, {
              __index = function(_, key)
                if key == "mods" then
                  forbidden.reads.mods = (forbidden.reads.mods or 0) + 1
                  return nil
                end
                if key == "game" or key == "storage" then
                  forbidden.reads[key] = (forbidden.reads[key] or 0) + 1
                  return nil
                end
                return _G[key]
              end,
              __newindex = function(table, key, value)
                if key == "game" or key == "storage" then
                  forbidden.writes[key] = value
                  return
                end
                rawset(table, key, value)
              end
            })

            local chunk, message = loadfile(path, "t", environment)
            if chunk == nil then return false, message, callbacks, forbidden, environment end
            local ok, result = pcall(chunk)
            return ok, result, callbacks, forbidden, environment
          end

          function assert_consumer_control_parse(path, active_mir, expected_callbacks)
            local ok, result, callbacks, forbidden, environment =
              parse_consumer_control(path, active_mir)
            assert(ok, tostring(result))
            assert(rawget(environment, "mods") == nil, "control created a mods global")
            assert(rawget(environment, "game") == nil and rawget(environment, "storage") == nil,
              "control created a game or storage global")
            assert(forbidden.reads.game == nil and forbidden.reads.storage == nil,
              "control parsed against game or storage")
            assert(forbidden.writes.game == nil and forbidden.writes.storage == nil,
              "control wrote game or storage")
            if expected_callbacks then
              assert(type(callbacks.on_init) == "function")
              assert(type(callbacks.on_load) == "function")
              assert(type(callbacks.on_configuration_changed) == "function")
              assert(type(callbacks.on_event) == "table"
                and callbacks.on_event.event == 1
                and type(callbacks.on_event.callback) == "function")
            else
              assert(next(callbacks) == nil, "optional consumer registered callbacks while MIR was absent")
            end
            return forbidden.reads.mods
          end

          function run_beta_production_final_tick(path, phase_output, observed_output, machine_bonus)
            local callbacks = {}
            local saves = 0
            local logged = 0
            local input = {
              get_item_count = function() return 0 end
            }
            local output = {
              get_item_count = function() return observed_output end,
              remove = function(item) return item.count end
            }
            local modules = {is_empty = function() return true end}
            local technology = {enabled = true, researched = true, level = 1}
            local force = {
              valid = true,
              index = 1,
              technologies = {['mir-api-fixture-beta-cable-1'] = technology},
              recipes = {['copper-cable'] = {productivity_bonus = 0.01}}
            }
            local machine = {
              valid = true,
              productivity_bonus = machine_bonus or 0,
              crafting_progress = 0,
              get_inventory = function(index)
                if index == 1 then return input end
                if index == 2 then return output end
                if index == 3 then return modules end
                error('unexpected inventory id ' .. tostring(index))
              end
            }
            local environment = {
              script = {
                active_mods = {
                  base = '2.1.23',
                  ['more-infinite-research'] = '5.0.21000',
                  ['mir-fixture-mir5-api-beta'] = '0.1.0'
                },
                on_init = function(callback) callbacks.on_init = callback end,
                on_load = function(callback) callbacks.on_load = callback end,
                on_event = function(event, callback) callbacks.on_event = {event = event, callback = callback} end
              },
              defines = {events = {on_tick = 1}, inventory = {
                crafter_input = 1, crafter_output = 2, crafter_modules = 3
              }},
              remote = {
                interfaces = {['more-infinite-research.api.v1'] = true},
                call = function(interface, method, force_index, technology_name)
                  assert(interface == 'more-infinite-research.api.v1')
                  assert(method == 'get_research')
                  assert(force_index == 1)
                  assert(technology_name == 'mir-api-fixture-beta-cable-1')
                  return {
                    name = technology_name, force_index = force_index, level = 1,
                    max_level = 1, researched = true, enabled = true
                  }
                end
              },
              helpers = {table_to_json = function() return '{}' end},
              log = function() logged = logged + 1 end,
              game = {
                tick = 1,
                forces = {player = force},
                server_save = function(name)
                  assert(name == 'mir5-native-complete')
                  saves = saves + 1
                end
              },
              storage = {}
            }
            environment._G = environment
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, 't', environment)
            assert(chunk ~= nil, message)
            assert(pcall(chunk))
            assert(type(callbacks.on_event) == 'table' and callbacks.on_event.event == 1)
            environment.storage.mir5_api_beta_production = {
              phase = 'researched', machine = machine,
              phase_plates_remaining = 0, phase_plates_inserted = 100,
              phase_refills = 1, phase_output = phase_output,
              baseline_plates_inserted = 100, researched_plates_inserted = 0,
              baseline_output = 200, researched_output = 0,
              research_completed_by_native_setter = true, deadline_tick = 100
            }
            local ok, message = pcall(callbacks.on_event.callback)
            local state = environment.storage.mir5_api_beta_production
            return ok, message, {
              phase = state.phase,
              saved = state.saved == true,
              phase_output = state.phase_output,
              researched_output = state.researched_output,
              server_saves = saves,
              marker_count = logged
            }
          end

          function run_module_permissions_init(path, omit_quality)
            local callbacks = {}
            local logged = 0
            local effects = {
              speed = true, productivity = true, consumption = true,
              pollution = true, quality = true
            }
            if omit_quality then effects.quality = nil end
            local categories = {
              speed = true, quality = true,
              ["mir5-module-permissions-fixture"] = true
            }
            local environment = {
              script = {
                active_mods = {
                  base = "2.1.23",
                  ["more-infinite-research"] = "5.0.21000",
                  ["mir-fixture-mir5-module-permissions"] = "0.1.0"
                },
                on_init = function(callback) callbacks.on_init = callback end
              },
              prototypes = {
                module_category = categories,
                recipe = {
                  ["mir5-module-permissions-recipe"] = {
                    allowed_effects = effects, allowed_module_categories = categories
                  },
                  ["mir5-module-permissions-parameter-recipe"] = {
                    allowed_effects = {}, allowed_module_categories = {speed = true}
                  }
                },
                entity = {
                  ["mir5-module-permissions-receiver"] = {
                    allowed_effects = effects, allowed_module_categories = categories
                  }
                }
              },
              helpers = {table_to_json = function() return "{}" end},
              log = function() logged = logged + 1 end
            }
            environment._G = environment
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk ~= nil, message)
            assert(pcall(chunk))
            assert(type(callbacks.on_init) == "function")
            local ok, result = pcall(callbacks.on_init)
            return ok, result, logged
          end
        """)

    def control(self, fixture):
        return (ROOT / "tests/mir5/fixtures" / fixture / "control.lua").as_posix()

    def test_lua_bootstrap_active_mods_is_the_pinned_runtime_dictionary(self):
        if not RUNTIME_API.is_file():
            self.skipTest("local Factorio runtime API documentation is not installed")
        document = json.loads(RUNTIME_API.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.1.23")
        bootstrap = next(row for row in document["classes"] if row["name"] == "LuaBootstrap")
        active_mods = next(field for field in bootstrap["attributes"] if field["name"] == "active_mods")
        self.assertEqual(
            active_mods["description"],
            "A dictionary listing the names of all currently active mods and mapping them to their version.",
        )
        self.assertFalse(active_mods["optional"])
        self.assertEqual(active_mods["read_type"], {
            "complex_type": "dictionary", "key": "string", "value": "string",
        })

    def test_both_controls_parse_with_mods_nil_and_runtime_mir_present(self):
        for fixture in ("api-alpha", "api-beta"):
            self.lua.globals().fixture_control = self.control(fixture)
            reads_mods = self.lua.eval(
                "assert_consumer_control_parse(fixture_control, true, true)"
            )
            self.assertIsNone(reads_mods, fixture)

    def test_alpha_control_keeps_its_required_runtime_registration_when_mir_is_absent(self):
        self.lua.globals().fixture_control = self.control("api-alpha")
        reads_mods = self.lua.eval(
            "assert_consumer_control_parse(fixture_control, false, true)"
        )
        self.assertIsNone(reads_mods)

    def test_beta_control_returns_before_runtime_registration_when_mir_is_absent(self):
        self.lua.globals().fixture_control = self.control("api-beta")
        reads_mods = self.lua.eval(
            "assert_consumer_control_parse(fixture_control, false, false)"
        )
        self.assertIsNone(reads_mods)

    def test_beta_production_final_tick_waits_for_output_and_finalizes_before_reload_oracle(self):
        self.lua.globals().fixture_control = self.control("api-beta-production")
        early_ok, early_error, early = self.lua.eval(
            "run_beta_production_final_tick(fixture_control, 200, 0)"
        )
        self.assertTrue(early_ok, early_error)
        self.assertEqual(early.phase, "researched")
        self.assertFalse(early.saved)
        self.assertEqual(early.phase_output, 200)
        self.assertEqual(early.server_saves, 0)
        self.assertEqual(early.marker_count, 0)

        complete_ok, complete_error, complete = self.lua.eval(
            "run_beta_production_final_tick(fixture_control, 202, 0)"
        )
        self.assertTrue(complete_ok, complete_error)
        self.assertEqual(complete.phase, "completed")
        self.assertTrue(complete.saved)
        self.assertEqual(complete.researched_output, 202)
        self.assertEqual(complete.server_saves, 1)
        self.assertEqual(complete.marker_count, 1)

    def test_beta_production_rejects_wrong_assembler_bonus_at_completed_output(self):
        self.lua.globals().fixture_control = self.control("api-beta-production")
        passed, message, state = self.lua.eval(
            "run_beta_production_final_tick(fixture_control, 202, 0, 0.01)"
        )
        self.assertFalse(passed)
        self.assertIn("native assembler productivity bonus differs", str(message))
        self.assertEqual(state.server_saves, 0)
        self.assertEqual(state.marker_count, 0)

    def test_relaxed_gear_setting_has_a_valid_native_range_that_clamps_the_saved_positive_cap(self):
        script = ROOT / "tests/mir5/fixtures/gear-upgrade-relaxed/settings-updates.lua"
        self.lua.execute('''
          data = {raw = {
            ['int-setting'] = {['ips-max-level-research_gears'] = {
              setting_type = 'startup', minimum_value = 0,
              maximum_value = 2147483647, default_value = 0
            }},
            ['string-setting'] = {['mir-settings-profile-import'] = {
              setting_type = 'startup', default_value = ''
            }}
          }}
        ''')
        self.lua.execute(script.read_text(encoding="utf-8"))
        self.lua.execute('''
          local setting = data.raw['int-setting']['ips-max-level-research_gears']
          assert(setting.minimum_value < setting.maximum_value)
          assert(setting.default_value == 0 and setting.maximum_value == 0)
          assert(math.max(setting.minimum_value, math.min(setting.maximum_value, 2)) == 0)
          assert(data.raw['string-setting']['mir-settings-profile-import'].default_value == '')
        ''')

    def test_module_permissions_create_only_callback_accepts_complete_public_maps_and_rejects_a_wrong_permission(self):
        self.lua.globals().fixture_control = self.control("module-permissions")
        ok, message, markers = self.lua.eval(
            "run_module_permissions_init(fixture_control, false)"
        )
        self.assertTrue(ok, message)
        self.assertEqual(markers, 1)

        wrong_ok, wrong_message, wrong_markers = self.lua.eval(
            "run_module_permissions_init(fixture_control, true)"
        )
        self.assertFalse(wrong_ok)
        self.assertIn("ordinary recipe native effects is missing quality", str(wrong_message))
        self.assertEqual(wrong_markers, 0)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(FixtureControlHostStageTests))
    sys.exit(0 if result.wasSuccessful() else 1)
