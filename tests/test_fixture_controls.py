"""Pure Lua 5.2 host-stage parse checks for MIR 5 API consumer controls."""
import argparse
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
F200_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F200_RUNTIME_API"),
    "D:/Games/Factorio/2.0/doc-html/runtime-api.json",
    "D:/Programs/Factorio/2.0/doc-html/runtime-api.json",
)
F210_RUNTIME_API_CANDIDATES = (
    os.environ.get("MIR_F210_RUNTIME_API"),
    "D:/Games/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
    "C:/Program Files/Steam/steamapps/common/Factorio/doc-html/runtime-api.json",
)


def f200_runtime_api_path():
    for candidate in F200_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


def f210_runtime_api_path():
    for candidate in F210_RUNTIME_API_CANDIDATES:
        if candidate:
            path = Path(candidate)
            if path.is_file():
                return path
    return None


class FixtureControlHostStageTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r"""
          function parse_consumer_control(path, active_mir, base_version, mir_version, beta_present)
            local callbacks = {}
            local forbidden = {reads = {}, writes = {}}
            local active_mods = {base = base_version or "2.1.23"}
            if active_mir then
              active_mods["more-infinite-research"] = mir_version or "5.0.21000"
            end
            if beta_present then active_mods["mir-fixture-mir5-api-beta"] = "0.1.0" end

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

          function assert_consumer_control_parse(path, active_mir, expected_callbacks, base_version, mir_version, beta_present)
            local ok, result, callbacks, forbidden, environment =
              parse_consumer_control(path, active_mir, base_version, mir_version, beta_present)
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

          function run_alpha_native_effect(path, observed_modifier)
            local callbacks = {}
            local logged = 0
            local alpha_state = {researched = false, level = 1, enabled = true}
            local force = {valid = true, index = 1, manual_crafting_speed_modifier = 0}
            local beta = {researched = false, level = 1, enabled = true}
            local alpha = {}
            setmetatable(alpha, {
              __index = function(_, key)
                if key == "prototype" then
                  return {effects = {{type = "character-crafting-speed", modifier = observed_modifier}}, max_level = 1}
                end
                return alpha_state[key]
              end,
              __newindex = function(_, key, value)
                if key == "researched" and alpha_state.researched ~= value and value then
                  force.manual_crafting_speed_modifier = force.manual_crafting_speed_modifier + observed_modifier
                end
                alpha_state[key] = value
              end
            })
            force.technologies = {
              automation = {researched = false},
              ["mir-api-fixture-alpha-2"] = {researched = false},
              ["mir-api-fixture-alpha-1"] = alpha,
              ["mir-api-fixture-beta-cable-1"] = beta
            }
            local environment = {
              script = {
                active_mods = {base = "2.0.77", ["more-infinite-research"] = "5.0.20000"},
                on_init = function(callback) callbacks.on_init = callback end,
                on_load = function(callback) callbacks.on_load = callback end,
                on_configuration_changed = function(callback) callbacks.on_configuration_changed = callback end,
                on_event = function(event, callback) callbacks.on_event = {event = event, callback = callback} end
              },
              defines = {events = {on_tick = 1}},
              remote = {
                interfaces = {["more-infinite-research.api.v1"] = true},
                call = function(interface, method, force_index, technology_name)
                  assert(interface == "more-infinite-research.api.v1")
                  if method == "get_version" then return {major = 1, minor = 0, product = "5.0.20000"} end
                  if method == "get_capabilities" then return {research_query = true} end
                  assert(method == "get_research")
                  if force_index ~= force.index then return nil, "force_not_found" end
                  if technology_name ~= "mir-api-fixture-alpha-1" then return nil, "technology_not_found" end
                  return {
                    name = technology_name, force_index = force_index, researched = alpha_state.researched,
                    level = alpha_state.level, enabled = alpha_state.enabled, max_level = 1
                  }
                end
              },
              helpers = {table_to_json = function() return "{}" end},
              log = function() logged = logged + 1 end,
              game = {tick = 1, forces = {player = force}}
            }
            environment._G = environment
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            assert(chunk ~= nil, message)
            assert(pcall(chunk))
            assert(type(callbacks.on_init) == "function")
            local ok, message = pcall(callbacks.on_init)
            return ok, message, {
              alpha_researched = alpha_state.researched,
              alpha_level = alpha_state.level,
              beta_researched = beta.researched,
              beta_level = beta.level,
              beta_enabled = beta.enabled,
              manual_crafting_speed_modifier = force.manual_crafting_speed_modifier,
              markers = logged
            }
          end

          function run_beta_production_final_tick(path, phase_output, observed_output, machine_bonus, base_version, mir_version)
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
                  base = base_version or '2.1.23',
                  ['more-infinite-research'] = mir_version or '5.0.21000',
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

          function run_module_permissions_init(path, omit_quality, enable_parameter_quality)
            local callbacks = {}
            local logged = 0
            local effects = {
              speed = true, productivity = true, consumption = true,
              pollution = true, quality = true
            }
            if omit_quality then effects.quality = nil end
            local disabled_effects = {
              speed = false, productivity = false, consumption = false,
              pollution = false, quality = false
            }
            if enable_parameter_quality then disabled_effects.quality = true end
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
                    allowed_effects = disabled_effects, allowed_module_categories = {speed = true}
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
        return (ROOT / "tests/fixtures" / fixture / "control.lua").as_posix()

    def test_api_consumer_f200_metadata_and_profile_select_one_exact_closure(self):
        expected = {
            "api-alpha": ["base >= 2.0.77", "more-infinite-research >= 5.0.20000"],
            "api-beta": ["base >= 2.0.77", "? more-infinite-research >= 5.0.20000"],
            "api-beta-production": [
                "base >= 2.0.77",
                "more-infinite-research = 5.0.20000",
                "mir-fixture-mir5-api-beta = 0.1.0",
            ],
        }
        for fixture, dependencies in expected.items():
            with self.subTest(fixture=fixture):
                info = json.loads(
                    (ROOT / "tests/fixtures" / fixture / "info-f200.json").read_text(encoding="utf-8")
                )
                self.assertEqual(info["name"], f"mir-fixture-mir5-{fixture}")
                self.assertEqual(info["version"], "0.1.0")
                self.assertEqual(info["factorio_version"], "2.0")
                self.assertEqual(info["dependencies"], dependencies)

        profile = json.loads(
            (ROOT / "tests/profiles/api-consumers-f200-2077.json").read_text(encoding="utf-8")
        )
        self.assertEqual(profile["kind"], "mir5-api-consumers-f200-native-selection")
        self.assertEqual(profile["target"], "f200")
        self.assertEqual(profile["factorio_line"], "2.0")
        self.assertEqual(profile["engine"]["version"], "2.0.77")
        self.assertEqual(profile["settings_mode"], "Defaults")
        self.assertEqual(
            [(row["name"], row["version"], row["enabled"]) for row in profile["mods"]],
            [
                ("base", "2.0.77", True),
                ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
                ("more-infinite-research", "5.0.20000", True),
                ("mir-fixture-mir5-api-alpha", "0.1.0", True),
                ("mir-fixture-mir5-api-beta", "0.1.0", True),
                ("mir-fixture-mir5-api-beta-production", "0.1.0", True),
            ],
        )

    def test_primary_f210_consumers_select_both_existing_independent_consumers(self):
        for fixture in ("api-alpha", "api-beta", "api-beta-production"):
            with self.subTest(fixture=fixture):
                info = json.loads((ROOT / "tests/fixtures" / fixture / "info.json").read_bytes())
                self.assertEqual(info["name"], f"mir-fixture-mir5-{fixture}")
                self.assertEqual(info["version"], "0.1.0")
                self.assertEqual(info["factorio_version"], "2.1")
                self.assertIn("base >= 2.1.23", info["dependencies"])
                self.assertTrue(any("5.0.21000" in dependency for dependency in info["dependencies"]))
        profile = json.loads((ROOT / "tests/profiles/api-consumers-f210-2123.json").read_bytes())
        self.assertEqual(profile["target"], "f210")
        self.assertEqual(profile["factorio_line"], "2.1")
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
        })
        self.assertEqual(profile["settings_mode"], "Defaults")
        self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]], [
            ("base", "2.1.23", True),
            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
            ("more-infinite-research", "5.0.21000", True),
            ("mir-fixture-mir5-api-alpha", "0.1.0", True),
            ("mir-fixture-mir5-api-beta", "0.1.0", True),
            ("mir-fixture-mir5-api-beta-production", "0.1.0", True),
        ])
        self.assertEqual(profile["archive_sha256"], {
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip":
                "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C",
        })

    def test_alpha_accepts_float32_native_effect_without_mutating_beta(self):
        self.lua.globals().fixture_control = self.control("api-alpha")
        actual_float32 = 0.05000000074505806
        self.lua.globals().observed_alpha_modifier = actual_float32
        passed, message, state = self.lua.eval(
            "run_alpha_native_effect(fixture_control, observed_alpha_modifier)"
        )
        self.assertTrue(passed, message)
        self.assertTrue(state.alpha_researched)
        self.assertAlmostEqual(state.manual_crafting_speed_modifier, 0.05, places=6)
        self.assertFalse(state.beta_researched)
        self.assertEqual(state.beta_level, 1)
        self.assertTrue(state.beta_enabled)
        self.assertEqual(state.markers, 1)

        self.lua.globals().observed_alpha_modifier = 0.04
        rejected, rejected_message, rejected_state = self.lua.eval(
            "run_alpha_native_effect(fixture_control, observed_alpha_modifier)"
        )
        self.assertFalse(rejected)
        self.assertIn("native character crafting speed effect differs", str(rejected_message))
        self.assertFalse(rejected_state.alpha_researched)
        self.assertFalse(rejected_state.beta_researched)
        self.assertEqual(rejected_state.manual_crafting_speed_modifier, 0)

    def test_lua_bootstrap_active_mods_is_the_pinned_runtime_dictionary(self):
        for runtime_api, version in ((f200_runtime_api_path(), "2.0.77"), (f210_runtime_api_path(), "2.1.23")):
            with self.subTest(version=version):
                if runtime_api is None:
                    self.skipTest("local Factorio runtime API documentation is not installed")
                document = json.loads(runtime_api.read_text(encoding="utf-8"))
                self.assertEqual(document["application_version"], version)
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

    def test_f200_documented_production_and_alpha_members_match_the_fixture_usage(self):
        runtime_api = f200_runtime_api_path()
        if runtime_api is None:
            self.skipTest("local Factorio 2.0 runtime API documentation is not installed")
        document = json.loads(runtime_api.read_text(encoding="utf-8"))
        self.assertEqual(document["application_version"], "2.0.77")
        classes = {row["name"]: row for row in document["classes"]}
        force = classes["LuaForce"]
        manual_crafting = next(
            field for field in force["attributes"] if field["name"] == "manual_crafting_speed_modifier"
        )
        self.assertEqual(manual_crafting["read_type"], "double")
        self.assertEqual(manual_crafting["write_type"], "double")
        recipe = classes["LuaRecipe"]
        productivity = next(field for field in recipe["attributes"] if field["name"] == "productivity_bonus")
        self.assertEqual(productivity["read_type"], "float")
        entity = classes["LuaEntity"]
        aggregate = next(field for field in entity["attributes"] if field["name"] == "productivity_bonus")
        self.assertEqual(aggregate["read_type"], "double")
        set_recipe = next(method for method in entity["methods"] if method["name"] == "set_recipe")
        self.assertEqual(set_recipe["parameters"][0]["name"], "quality")
        self.assertEqual(set_recipe["parameters"][1]["name"], "recipe")
        self.assertEqual(set_recipe["return_values"][0]["type"], {
            "complex_type": "array", "value": "ItemWithQualityCount",
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

    def test_beta_native_float_readback_keeps_exact_recipe_and_rejects_effect_drift(self):
        run = self.lua.eval(r'''function(path, change)
          local ok,message,callbacks,_,env=parse_consumer_control(path,true,"2.0.77","5.0.20000",true)
          assert(ok,message)
          local name="mir-api-fixture-beta-cable-1"
          local native={level=1,enabled=true,researched=false,
            prototype={effects={{type="change-recipe-productivity",recipe="copper-cable",change=change}}}}
          local force={index=1,valid=true,manual_crafting_speed_modifier=0,technologies={[name]=native}}
          rawset(env,"game",{tick=1,forces={player=force}})
          rawset(env,"helpers",{table_to_json=function()return "{}"end})
          rawset(env,"remote",{interfaces={["more-infinite-research.api.v1"]=true},call=function(_,method,index,id)
            if method=="get_version"then return {major=1,minor=0}end
            if method=="get_capabilities"then return {research_query=true}end
            assert(method=="get_research")
            if index~=1 then return nil,"force_not_found"end
            if id~=name then return nil,"technology_not_found"end
            return {name=name,force_index=1,level=1,max_level=1,enabled=true,researched=false}
          end})
          local passed,result=pcall(callbacks.on_init)
          assert(native.researched==false and native.level==1 and force.manual_crafting_speed_modifier==0)
          return passed,tostring(result)
        end''')
        passed, message = run(self.control("api-beta"), 0.009999999776482582)
        self.assertTrue(passed, message)
        passed, message = run(self.control("api-beta"), 0.02)
        self.assertFalse(passed)
        self.assertIn("native cable productivity effect differs", message)

    def test_beta_production_accepts_f200_closure_and_rejects_an_unsupported_target(self):
        self.lua.globals().fixture_control = self.control("api-beta-production")
        passed, message, callbacks, forbidden, _ = self.lua.eval(
            "parse_consumer_control(fixture_control, true, '2.0.77', '5.0.20000', true)"
        )
        self.assertTrue(passed, message)
        self.assertIsNotNone(callbacks.on_init)
        self.assertIsNotNone(callbacks.on_load)
        self.assertIsNotNone(callbacks.on_event)
        self.assertEqual(len(forbidden.reads), 0)

        passed, message, callbacks, forbidden, _ = self.lua.eval(
            "parse_consumer_control(fixture_control, true, '2.0.76', '5.0.20000', true)"
        )
        self.assertFalse(passed)
        self.assertIn("unsupported Factorio, MIR, or API-beta closure", str(message))
        self.assertEqual(len(callbacks), 0)
        self.assertEqual(len(forbidden.reads), 0)

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

        f200_ok, f200_error, f200 = self.lua.eval(
            "run_beta_production_final_tick(fixture_control, 202, 0, nil, '2.0.77', '5.0.20000')"
        )
        self.assertTrue(f200_ok, f200_error)
        self.assertEqual(f200.phase, "completed")
        self.assertTrue(f200.saved)
        self.assertEqual(f200.researched_output, 202)
        self.assertEqual(f200.server_saves, 1)
        self.assertEqual(f200.marker_count, 1)

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
        script = ROOT / "tests/fixtures/gear-upgrade-relaxed/settings-updates.lua"
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

    def test_worker_fixture_ranges_are_native_valid_and_clamp_both_configuration_directions(self):
        for fixture, saved, expected in (
            ("worker-speed-precap", 7, 0),
            ("worker-speed-cap", 0, 7),
            ("worker-speed-cap-relaxed", 7, 0),
        ):
            with self.subTest(fixture=fixture):
                self.lua.execute('''
                  data = {raw = {['int-setting'] = {['mir-max-level-worker-robots-speed'] = {
                    setting_type = 'startup', minimum_value = 0,
                    maximum_value = 2147483647, default_value = 0
                  }}}}
                ''')
                script = ROOT / "tests/fixtures" / fixture / "settings-updates.lua"
                self.lua.execute(script.read_text(encoding="utf-8"))
                minimum, maximum, default = self.lua.eval('''function()
                  local value = data.raw['int-setting']['mir-max-level-worker-robots-speed']
                  return value.minimum_value, value.maximum_value, value.default_value
                end''')()
                self.assertLess(minimum, maximum, "Factorio rejects an empty native setting range")
                self.assertLessEqual(minimum, default)
                self.assertLessEqual(default, maximum)
                self.assertEqual(max(minimum, min(maximum, saved)), expected)

    def test_module_permissions_create_only_callback_accepts_false_effect_masks_and_rejects_wrong_permissions(self):
        self.lua.globals().fixture_control = self.control("module-permissions")
        ok, message, markers = self.lua.eval(
            "run_module_permissions_init(fixture_control, false, false)"
        )
        self.assertTrue(ok, message)
        self.assertEqual(markers, 1)

        wrong_ok, wrong_message, wrong_markers = self.lua.eval(
            "run_module_permissions_init(fixture_control, true, false)"
        )
        self.assertFalse(wrong_ok)
        self.assertIn("ordinary recipe native effects is missing quality", str(wrong_message))
        self.assertEqual(wrong_markers, 0)

        parameter_ok, parameter_message, parameter_markers = self.lua.eval(
            "run_module_permissions_init(fixture_control, false, true)"
        )
        self.assertFalse(parameter_ok)
        self.assertIn(
            "parameter recipe native effects unexpectedly enables quality",
            str(parameter_message),
        )
        self.assertEqual(parameter_markers, 0)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(FixtureControlHostStageTests))
    sys.exit(0 if result.wasSuccessful() else 1)
