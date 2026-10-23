"""Pure Lua 5.2 controls for explicit MIR5 control/data-stage composition.

These tests exercise only registration and callback routing with host doubles.
They are not Factorio engine, GUI, menu, save, or gameplay evidence.
"""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.globals().data_source = (ROOT / "source/mir5/data.lua").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          function install_modules(caps_enabled, repair_enabled, scripted_active)
            CAP_ACTIVE = caps_enabled == true
            REPAIR_ACTIVE = repair_enabled == true
            SCRIPTED_ACTIVE = scripted_active == true
            lifecycle_calls = {}
            library_calls = {}
            scripted_calls = {}
            library_pending = false
            package.preload["research.settings"] = function()
              return {resolve = function() return {passive_repair_enabled = REPAIR_ACTIVE} end}
            end
            package.preload["runtime.settings_profile"] = function()
              return {
                export_string = function(options) return "exported-profile", options end,
                validate_string = function(text) return {valid = text == "valid-profile"} end
              }
            end
            package.preload["runtime.settings_commands"] = function()
              return {
                export = function(command) library_calls.profile_export = command end,
                validate = function(command) library_calls.profile_validate = command end
              }
            end
            package.preload["runtime.lifecycle"] = function()
              return {
                cap_limits = function(force)
                  lifecycle_calls.cap_force = force
                  return { ["recipe-prod-research_gears-1"] = 2 }
                end,
                caps_active = function() return CAP_ACTIVE end,
                on_init = function() lifecycle_calls.init = (lifecycle_calls.init or 0) + 1 end,
                on_configuration_changed = function(event)
                  lifecycle_calls.configuration = event
                end,
                on_load = function() lifecycle_calls.load = (lifecycle_calls.load or 0) + 1 end,
                on_force_created = function(event) lifecycle_calls.force_created = event end,
                on_force_reset = function(event) lifecycle_calls.force_reset = event end,
                on_forces_merged = function(event) lifecycle_calls.forces_merged = event end,
                on_research_finished = function(event) lifecycle_calls.research_finished = event end,
                on_research_reversed = function(event) lifecycle_calls.research_reversed = event end,
                on_technology_effects_reset = function(event) lifecycle_calls.effects_reset = event end,
                on_research_started = function(event) lifecycle_calls.research_started = event end,
                on_research_cancelled = function(event) lifecycle_calls.research_cancelled = event end
              }
            end
            package.preload["runtime.scripted_effects"] = function()
              return {
                events_active = function() return SCRIPTED_ACTIVE end,
                agriculture_events_active = function() return SCRIPTED_ACTIVE end,
                on_init = function() scripted_calls.init = (scripted_calls.init or 0) + 1 end,
                on_configuration_changed = function(event) scripted_calls.configuration = event end,
                on_load = function() scripted_calls.load = (scripted_calls.load or 0) + 1 end,
                on_research_finished = function(event) scripted_calls.research_finished = event end,
                on_research_reversed = function(event) scripted_calls.research_reversed = event end,
                on_technology_effects_reset = function(event) scripted_calls.effects_reset = event end,
                on_tower_planted_seed = function(event) scripted_calls.tower = event end,
                on_force_created = function(event) scripted_calls.force_created = event end,
                on_force_reset = function(event) scripted_calls.force_reset = event end,
                on_forces_merged = function(event) scripted_calls.forces_merged = event end
              }
            end
            package.preload["runtime.library"] = function()
              local module = {}
              module.translation_maintenance_ticks = 61
              module.set_cap_provider = function(provider) library_calls.provider = provider end
              module.subscription_needs = function() return library_pending == true end
              module.open = function(player, options)
                library_calls.open = {player = player, options = options}
                return player.frame
              end
              module.on_init = function() library_calls.init = (library_calls.init or 0) + 1 end
              module.on_configuration_changed = function(event) library_calls.configuration = event end
              module.on_load = function() library_calls.load = (library_calls.load or 0) + 1 end
              module.on_lua_shortcut = function(event) library_calls.shortcut = event end
              module.on_gui_text_changed = function(event) library_calls.text = event end
              module.on_gui_selected_tab_changed = function(event) library_calls.tab = event end
              module.on_gui_selection_state_changed = function(event) library_calls.selection = event end
              module.on_gui_click = function(event) library_calls.click = event end
              module.on_gui_location_changed = function(event) library_calls.location = event end
              module.on_gui_closed = function(event) library_calls.closed = event end
              module.on_player_removed = function(event) library_calls.removed = event end
              module.on_string_translated = function(event) library_calls.translated = event end
              module.on_player_locale_changed = function(event) library_calls.locale = event end
              module.on_player_changed_force = function(event) library_calls.force = event end
              module.on_player_joined_game = function(event) library_calls.joined = event end
              module.on_translation_maintenance = function(event) library_calls.translation_tick = event end
              return module
            end
            package.preload["api.v1.runtime"] = function()
              return {
                get_version = function() return {major = 1} end,
                get_capabilities = function() return {research_query = true} end,
                get_research = function() return {name = "gear"} end
              }
            end
          end

          function install_runtime(foreign_interfaces, active_mods)
            handlers = {events = {}, filters = {}, nth = {}, nth_calls = 0}
            settings = {startup = {}}
            storage = {}
            remote = {interfaces = foreign_interfaces or {}}
            remote.add_interface = function(name, members)
              remote.interfaces[name] = members
            end
            commands = {registered = {}}
            commands.add_command = function(name, help, callback)
              commands.registered[name] = {help = help, callback = callback}
            end
            script = {
              active_mods = active_mods or {},
              on_init = function(callback) handlers.init = callback end,
              on_configuration_changed = function(callback) handlers.configuration = callback end,
              on_load = function(callback) handlers.load = callback end,
              on_event = function(id, callback, filters)
                handlers.events[id], handlers.filters[id] = callback, filters
              end,
              on_nth_tick = function(interval, callback)
                handlers.nth[interval] = callback
                handlers.nth_calls = handlers.nth_calls + 1
              end
            }
            defines = {events = {
              on_force_created = 1, on_force_reset = 2, on_forces_merged = 3,
              on_research_finished = 4, on_research_started = 5, on_research_cancelled = 6,
              on_lua_shortcut = 7, on_gui_text_changed = 8,
              on_gui_selection_state_changed = 9, on_gui_click = 10,
              on_gui_location_changed = 11, on_gui_closed = 12, on_player_removed = 13,
              on_entity_damaged = 14, on_string_translated = 15,
              on_player_locale_changed = 16, on_player_changed_force = 17,
              on_player_joined_game = 18, on_research_reversed = 19,
              on_technology_effects_reset = 20, on_gui_selected_tab_changed = 21
            }}
            known_technology = {valid = true, name = "recipe-prod-research_gears-1"}
            player = {valid = true, index = 1, frame = {valid = true},
              force = {technologies = {[known_technology.name] = known_technology}}}
            game = {get_player = function(index) return index == 1 and player or nil end}
          end

          function load_control()
            package.loaded["control"] = nil
            package.loaded["runtime.bootstrap"] = nil
            package.loaded["runtime.configuration"] = nil
            package.loaded["runtime.lifecycle"] = nil
            package.loaded["runtime.scripted_effects"] = nil
            package.loaded["runtime.library"] = nil
            package.loaded["api.v1.runtime"] = nil
            package.loaded["runtime.settings_profile"] = nil
            package.loaded["runtime.settings_commands"] = nil
            package.loaded["research.settings"] = nil
            return require("control")
          end
        ''')

    def test_control_composes_lifecycle_library_api_legacy_interface_and_command(self):
        self.lua.execute('''
          install_modules(true); install_runtime(); load_control()
          local api = remote.interfaces["more-infinite-research.api.v1"]
          assert(type(api) == "table" and type(api.get_version) == "function"
            and type(api.get_capabilities) == "function" and type(api.get_research) == "function")
          local browser = remote.interfaces["more-infinite-research-browser"]
          assert(type(browser) == "table" and type(browser.open) == "function")
          local profiles = remote.interfaces["more-infinite-research-settings"]
          assert(type(profiles.export_string) == "function" and type(profiles.validate_string) == "function")
          assert(profiles.export_string({compact = true}) == "exported-profile")
          assert(profiles.validate_string("valid-profile").valid == true)
          assert(profiles.get_research == nil and profiles.apply == nil)
          commands.registered["mir-settings-export"].callback({parameter = "--compact"})
          commands.registered["mir-settings-import-check"].callback({parameter = "valid-profile"})
          assert(library_calls.profile_export.parameter == "--compact")
          assert(library_calls.profile_validate.parameter == "valid-profile")
          assert(commands.registered["mir-research"].help[1] == "mir-browser.command")

          assert(type(handlers.init) == "function" and type(handlers.configuration) == "function"
            and type(handlers.load) == "function")
          handlers.init(); handlers.configuration({mod_changes = {}}); handlers.load()
          assert(lifecycle_calls.init == 1 and library_calls.init == 1)
          assert(lifecycle_calls.configuration.mod_changes and library_calls.configuration.mod_changes)
          assert(lifecycle_calls.load == 1 and library_calls.load == 1)

          for id = 1, 6 do assert(type(handlers.events[id]) == "function") end
          assert(type(handlers.events[19]) == "function" and type(handlers.events[20]) == "function")
          assert(handlers.events[1] == nil or handlers.events[1] ~= handlers.events[7])
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
          assert(type(handlers.events[21]) == "function")
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
          assert(handlers.events[14] == nil and handlers.nth[60] == nil and handlers.nth[61] == nil and storage.mir == nil)
          handlers.events[7]({player_index = 1})
          handlers.events[8]({player_index = 1})
          handlers.events[21]({player_index = 1})
          handlers.events[9]({player_index = 1})
          handlers.events[10]({player_index = 1})
          handlers.events[11]({player_index = 1})
          handlers.events[12]({player_index = 1})
          handlers.events[13]({player_index = 1})
          handlers.events[15]({player_index = 1, id = 1, translated = true, result = "Gear"})
          handlers.events[16]({player_index = 1})
          handlers.events[17]({player_index = 1})
          handlers.events[18]({player_index = 1})
          handlers.events[19]({research = known_technology})
          handlers.events[20]({force = player.force})
          assert(library_calls.shortcut.player_index == 1 and library_calls.text.player_index == 1
            and library_calls.tab.player_index == 1)
          assert(library_calls.selection.player_index == 1 and library_calls.click.player_index == 1)
          assert(library_calls.location.player_index == 1 and library_calls.closed.player_index == 1
            and library_calls.removed.player_index == 1)
          assert(library_calls.translated.result == "Gear" and library_calls.locale.player_index == 1
            and library_calls.force.player_index == 1 and library_calls.joined.player_index == 1)
          assert(lifecycle_calls.research_reversed.research == known_technology
            and lifecycle_calls.effects_reset.force == player.force)

          library_pending = true
          handlers.events[15]({player_index = 1, id = 2, translated = false, result = "unused"})
          assert(type(handlers.nth[61]) == "function")
          handlers.nth[61]({tick = 61})
          assert(library_calls.translation_tick.tick == 61)
          library_pending = false
          handlers.events[15]({player_index = 1, id = 3, translated = false, result = "unused"})
          assert(handlers.nth[61] == nil)

          local cap_map = library_calls.provider(player.force)
          assert(cap_map[known_technology.name] == 2 and lifecycle_calls.cap_force == player.force)
          assert(browser.open(77, {}) == false and library_calls.open == nil)
          local hidden = {known_technology.name}
          assert(browser.open(1, {search = "gear", family = "mir", selected = known_technology.name,
            status = 4, mode = 3, sort = "name-desc", page = 7, hidden = hidden}))
          assert(library_calls.open.player == player and library_calls.open.options.query == "gear")
          assert(library_calls.open.options.family == "mir"
            and library_calls.open.options.selected == known_technology.name
            and library_calls.open.options.status == 4 and library_calls.open.options.mode == 3
            and library_calls.open.options.sort == "name-desc"
            and library_calls.open.options.page == 7 and library_calls.open.options.hidden == hidden)
          assert(browser.open(1, {family = "research_gears", visibility = 2}))
          assert(library_calls.open.options.family == "research_gears"
            and library_calls.open.options.visibility == 2)
          assert(browser.open(1, {visibility = 3}))
          assert(library_calls.open.options.visibility == nil)
          assert(browser.open(1, {page = 30000}))
          assert(library_calls.open.options.page == 30000)
          assert(browser.open(1, {page = 0}))
          assert(library_calls.open.options.page == nil)
          assert(browser.open(1, {page = 1.5}))
          assert(library_calls.open.options.page == nil)
          for _, accepted_mode in ipairs({1, 2, 3}) do
            assert(browser.open(1, {mode = accepted_mode}))
            assert(library_calls.open.options.mode == accepted_mode)
          end
          for _, invalid_mode in ipairs({0, 4, 1.5, "2", 0/0}) do
            assert(browser.open(1, {mode = invalid_mode}))
            assert(library_calls.open.options.mode == nil)
          end
          assert(browser.open(1, {selected = "unknown", family = "not-a-family", status = 5,
            sort = "invalid", page = 30001, hidden = "not-a-list"}))
          assert(library_calls.open.options.family == nil and library_calls.open.options.selected == nil
            and library_calls.open.options.status == nil and library_calls.open.options.sort == nil
            and library_calls.open.options.page == nil and library_calls.open.options.hidden == nil)
          local original_force = player.force
          player.force = setmetatable({}, {__index = function(_, key)
            error("oversized remote selection touched native force: " .. tostring(key))
          end})
          assert(browser.open(1, {selected = string.rep("x", 161)}))
          assert(library_calls.open.options.selected == nil)
          player.force = original_force
          commands.registered["mir-research"].callback({player_index = 1})
          assert(library_calls.open.player == player and library_calls.open.options == nil)
        ''')

    def test_unlimited_control_omits_only_cap_event_callbacks(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          for id = 1, 6 do assert(handlers.events[id] == nil) end
          assert(handlers.events[19] == nil and handlers.events[20] == nil)
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
        ''')

    def test_unlimited_scripted_effects_register_and_route_force_lifecycle_events(self):
        self.lua.execute('''
          scripted_calls = {}
          install_modules(false, false, true)
          install_runtime(nil, {['space-age'] = '2.1.23'})
          load_control()
          for id = 1, 4 do
            assert(type(handlers.events[id]) == "function", "missing event " .. tostring(id))
          end
          assert(type(handlers.events[19]) == "function" and type(handlers.events[20]) == "function")
          assert(handlers.events[5] == nil and handlers.events[6] == nil)
          local created, reset, destination = {name = "created"}, {name = "reset"}, {name = "destination"}
          handlers.events[1]({force = created})
          handlers.events[2]({force = reset})
          handlers.events[3]({source_index = 31, destination = destination})
          handlers.events[19]({research = {name = "scripted"}})
          handlers.events[20]({force = destination})
          assert(scripted_calls.force_created.force == created
            and scripted_calls.force_reset.force == reset
            and scripted_calls.forces_merged.source_index == 31
            and scripted_calls.forces_merged.destination == destination)
          assert(lifecycle_calls.force_created == nil and lifecycle_calls.force_reset == nil
            and lifecycle_calls.forces_merged == nil and lifecycle_calls.research_reversed == nil
            and lifecycle_calls.effects_reset == nil,
            "unlimited cap lifecycle received a scripted-only force callback")
          assert(scripted_calls.research_reversed.research.name == "scripted"
            and scripted_calls.effects_reset.force == destination)
        ''')

    def test_base_configuration_retires_a_persisted_spoilage_contribution_without_loading_space_age_body(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          local raw = {spoil_time_modifier = 2.2}
          local difficulty = setmetatable({writes = 0}, {
            __index = function(_, key) return raw[key] end,
            __newindex = function(self, key, value)
              if key == "spoil_time_modifier" then
                raw[key] = value
                rawset(self, "writes", self.writes + 1)
              else
                rawset(self, key, value)
              end
            end
          })
          game.difficulty_settings = difficulty
          storage.mir = {unrelated = "retain", spoilage_preservation = {
            baseline = 2, effective_level = 2, applied_multiplier = 1.1, last_applied_value = 2.2
          }}
          assert(package.loaded["runtime.scripted_effects"] == nil,
            "base-only control loaded the active Space Age body")
          handlers.configuration({mod_changes = {['space-age'] = {old_version = '2.1.23'}}})
          assert(difficulty.spoil_time_modifier == 2 and difficulty.writes == 1)
          assert(storage.mir.spoilage_preservation == nil and storage.mir.unrelated == "retain")
          handlers.configuration({mod_changes = {}})
          assert(difficulty.writes == 1, "removal cleanup was not idempotent")

          local writes_before_malformed = difficulty.writes
          storage.mir.spoilage_preservation = {baseline = 0, applied_multiplier = 1.1,
            last_applied_value = 2.2}
          handlers.configuration({mod_changes = {}})
          assert(storage.mir.spoilage_preservation == nil and difficulty.writes == writes_before_malformed,
            "malformed removal state wrote a native property or remained durable")

          raw.spoil_time_modifier = 9
          storage.mir.spoilage_preservation = {baseline = 2, effective_level = 2,
            applied_multiplier = 1.1, last_applied_value = 2.2}
          local writes_before_foreign = difficulty.writes
          handlers.configuration({mod_changes = {}})
          assert(difficulty.spoil_time_modifier == 9 and difficulty.writes == writes_before_foreign
            and storage.mir.spoilage_preservation == nil,
            "base removal overwrote a foreign shared-modifier value")
        ''')

    def test_base_removal_retains_state_when_the_spoilage_property_is_unavailable(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          local preserved = {baseline = 2, effective_level = 2,
            applied_multiplier = 1.1, last_applied_value = 2.2}
          local difficulty = setmetatable({}, {
            __index = function(_, key)
              if key == "spoil_time_modifier" then error("Space Age property is unavailable") end
            end,
            __newindex = function(_, key)
              error("Space Age property must not be written: " .. tostring(key))
            end
          })
          game.difficulty_settings = difficulty
          storage.mir = {spoilage_preservation = preserved}
          assert(package.loaded["runtime.scripted_effects"] == nil,
            "base-only removal loaded the active Space Age body")
          handlers.configuration({mod_changes = {['space-age'] = {old_version = '2.1.23'}}})
          assert(storage.mir.spoilage_preservation == preserved,
            "unavailable native property discarded a contribution needed for re-addition")
        ''')

    def test_catalogue_declares_full_base_and_space_age_cap_identities_with_detached_metadata(self):
        self.lua.execute('''
          script, mods = {active_mods = {}}, {}
          package.loaded["research.catalogue"] = nil
          local catalogue = require("research.catalogue")
          local first, second = catalogue.declared(), catalogue.declared()
          assert(#first == 53 and #second == 53)
          local seen, continuations = {}, 0
          for _, row in ipairs(first) do
            assert(type(row.id) == "string" and seen[row.id] == nil)
            seen[row.id] = true
            assert(row.ownership_kind == "authored_generated"
              and type(row.family) == "string" and type(row.cap_setting) == "string")
            assert(type(row.legacy_binding) == "table")
            if row.legacy_binding.source == "base-continuation" then
              continuations = continuations + 1
              assert(row.legacy_binding.operation == "emit_base_extension")
            else
              assert(row.legacy_binding.source == "generated-stream"
                and row.legacy_binding.operation == "emit")
            end
          end
          assert(continuations == 6 and seen["recipe-prod-research_gears-1"])
          first[1].settings[1] = "foreign"
          assert(second[1].settings[1] == "ips-enable-research_gears")

          script.active_mods, mods = {['space-age'] = '2.1.23'}, {['space-age'] = '2.1.23'}
          package.loaded["research.catalogue"] = nil
          local space_age = require("research.catalogue").declared()
          local generated, native = 0, 0
          for _, row in ipairs(space_age) do
            if row.ownership_kind == "authored_generated" then
              generated = generated + 1
            else
              native = native + 1
              assert(row.ownership_kind == "nativeowner" and row.native_owner_identity == row.id)
              assert(row.legacy_binding.source == "native-owner"
                and row.legacy_binding.operation == "preserve_native_owner")
              assert(row.native_admission.effect_type == "change-recipe-productivity"
                and #row.native_admission.recipes > 0)
            end
          end
          assert(#space_age == 76 and generated == 71 and native == 5)
        ''')

    def test_interface_collisions_are_rejected_without_replacement(self):
        self.lua.execute('''
          local foreign_api = {}; install_modules(false)
          install_runtime({["more-infinite-research.api.v1"] = foreign_api})
          local ok, message = pcall(load_control)
          assert(not ok and tostring(message):find("MIR API interface collision", 1, true))
          assert(remote.interfaces["more-infinite-research.api.v1"] == foreign_api)

          local foreign_browser = {}; install_modules(false)
          install_runtime({["more-infinite-research-browser"] = foreign_browser})
          ok, message = pcall(load_control)
          assert(not ok and tostring(message):find("MIR Research Library interface collision", 1, true))
          assert(remote.interfaces["more-infinite-research-browser"] == foreign_browser)

          local foreign_settings = {}; install_modules(false)
          install_runtime({["more-infinite-research-settings"] = foreign_settings})
          ok, message = pcall(load_control)
          assert(not ok and tostring(message):find("MIR Settings profile interface collision", 1, true))
          assert(remote.interfaces["more-infinite-research-settings"] == foreign_settings)
        ''')

    def test_repair_subscribes_only_for_pending_work_and_preserves_native_rate(self):
        self.lua.execute('''
          install_modules(false, true); install_runtime(); load_control(); handlers.init()
          assert(handlers.nth[60] == nil and storage.mir == nil)
          local damage = handlers.events[14]
          assert(type(damage) == "function" and #handlers.filters[14] == 2)
          assert(handlers.filters[14][1].filter == "type" and handlers.filters[14][1].type == "wall")
          assert(handlers.filters[14][2].type == "gate" and handlers.filters[14][2].mode == "or")
          local owner = {valid = true, name = "player", index = 1}
          game.forces = {player = owner}
          local wall = {valid = true, type = "wall", unit_number = 1, force = owner,
            surface = {index = 1}, health = 9, max_health = 10}
          damage({entity = wall, tick = 0})
          assert(#storage.mir.passive_repair.queue == 1 and type(handlers.nth[60]) == "function")
          local registrations = handlers.nth_calls
          damage({entity = wall, tick = 60})
          assert(handlers.nth_calls == registrations and #storage.mir.passive_repair.queue == 1)
          handlers.nth[60]({tick = 600})
          assert(wall.health == 9 and type(handlers.nth[60]) == "function")
          handlers.nth[60]({tick = 660})
          assert(wall.health == 10 and handlers.nth[60] == nil)
          assert(#storage.mir.passive_repair.queue == 0 and not storage.mir.passive_repair.scheduled)
          for id = 1, 6 do assert(handlers.events[id] == nil) end
        ''')

    def test_repair_load_reconnects_without_save_writes_or_game_access_and_disable_clears(self):
        self.lua.execute('''
          install_modules(false, true); install_runtime(); load_control()
          local members = {[7] = {retained = true}}
          local queue = {7}
          local bucket = {queue = queue, members = members, scheduled = false, unknown = "keep"}
          storage.mir = {passive_repair = bucket, historical_other = "keep"}
          game = setmetatable({}, {__index = function() error("on_load accessed game") end})
          handlers.load()
          assert(type(handlers.nth[60]) == "function")
          assert(storage.mir.passive_repair == bucket and bucket.queue == queue and bucket.members == members)
          assert(bucket.scheduled == false and bucket.unknown == "keep" and storage.mir.historical_other == "keep")

          install_modules(false, false); remote.interfaces = {}; load_control()
          assert(handlers.events[14] == nil and handlers.nth[60] == nil)
          handlers.configuration({})
          assert(storage.mir.passive_repair == bucket and #bucket.queue == 0 and next(bucket.members) == nil)
          assert(bucket.scheduled == false and bucket.unknown == "keep" and storage.mir.historical_other == "keep")

          storage.mir = "unversioned malformed namespace"
          handlers.load()
          assert(storage.mir == "unversioned malformed namespace" and handlers.nth[60] == nil)
          storage.mir = {passive_repair = "unversioned malformed bucket", historical_other = "keep"}
          handlers.load()
          assert(storage.mir.passive_repair == "unversioned malformed bucket"
            and storage.mir.historical_other == "keep" and handlers.nth[60] == nil)
        ''')

    def test_data_stage_emits_only_the_published_shortcut_identity(self):
        self.lua.execute('''
          local function capture(space_age)
            emitted = nil
            mods = space_age and {["space-age"] = "2.0.0"} or {}
            data = {extend = function(_, rows) emitted = rows end}
            assert(loadfile(data_source))()
            assert(#emitted == 1)
            return emitted[1]
          end
          local base = capture(false)
          assert(base.type == "shortcut" and base.name == "mir-research-browser"
            and base.action == "lua" and base.toggleable
            and base.order == "z[more-infinite-research]-a[research-browser]")
          assert(base.icon == "__base__/graphics/icons/lab.png" and base.icon_size == 64)
          local space_age = capture(true)
          assert(space_age.icon == "__space-age__/graphics/technology/research-productivity.png"
            and space_age.icon_size == 256)
        ''')

    def test_bootstrap_has_no_late_module_loading_or_unconditional_tick_dispatch(self):
        source = (ROOT / "source/mir5/runtime/bootstrap.lua").read_text(encoding="utf-8")
        control = (ROOT / "source/mir5/control.lua").read_text(encoding="utf-8")
        self.assertNotIn("on_tick", source)
        self.assertNotIn("require(", source[source.index("function M.register"):])
        self.assertIn('require("runtime.bootstrap")', control)
        self.assertIn("remote.add_interface", control)

    def test_k2_carrier_lifecycle_is_independent_of_caps_and_scripted_features(self):
        self.lua.execute('''
          install_modules(false,false,false)
          install_runtime({}, {base="2.1.23",["space-age"]="2.1.23",Krastorio2="2.1.4",
            ["Krastorio2-spaced-out"]="2.0.19",Krastorio2Assets="2.0.0",["k2so-assets"]="1.0.0"})
          package.preload["research.settings"] = function()
            return {resolve=function() return {passive_repair_enabled=false,
              streams={research_material_imersite={effect_percent=6}}} end}
          end
          local initialized,reconciled = {},{}
          package.preload["runtime.k2_imersite_migration"] = function()
            return {
              initialize_force=function(force,change)
                assert(change == .06); initialized[#initialized+1]=force.index
              end,
              reconcile_force=function(force,change,records)
                assert(change == .06); reconciled[#reconciled+1]=force.index
                records[force.index]={status="completed"}
              end
            }
          end
          local one,two = {index=1},{index=2}
          game.forces={one}
          load_control()
          for id=1,3 do assert(type(handlers.events[id]) == "function") end
          assert(handlers.events[4] == nil and handlers.events[5] == nil and handlers.events[6] == nil)
          assert(storage.mir_k2_imersite_state == nil)
          handlers.init()
          assert(initialized[1] == 1 and storage.mir_k2_imersite_state == nil)
          handlers.configuration({mod_changes={}})
          assert(reconciled[1] == 1 and storage.mir_k2_imersite_state.forces[1])
          handlers.events[1]({force=two})
          handlers.events[3]({source_index=1,destination=two})
          assert(initialized[2] == 2 and initialized[3] == 2 and reconciled[2] == 2)
          assert(storage.mir_k2_imersite_state.forces[1] == nil and storage.mir_k2_imersite_state.forces[2])
          handlers.events[2]({force=two})
          assert(initialized[4] == 2 and storage.mir_k2_imersite_state.forces[2] == nil)
          game=nil
          handlers.load()
          assert(#initialized == 4 and #reconciled == 2)
          assert(lifecycle_calls.force_created == nil and lifecycle_calls.force_reset == nil
            and lifecycle_calls.forces_merged == nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BootstrapTests))
    sys.exit(0 if result.wasSuccessful() else 1)
