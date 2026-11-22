"""Explicit construction for the bootstrap host-control world."""
from pathlib import Path

from worker_storage_recovery_fixture import MINIMAL_NATIVE_FACTS


def build_bootstrap_control_world(runtime_factory, *, source_root):
    """Create the bootstrap host-control world from caller-owned inputs."""
    lua = runtime_factory(unpack_returned_tuples=True)
    return install_bootstrap_control_world(lua, source_root=source_root)


def install_bootstrap_control_world(lua, *, source_root):
    """Install the bootstrap host doubles into an existing caller-owned Lua world."""
    lua.globals().player_root = Path(source_root).as_posix()
    lua.globals().data_source = (Path(source_root) / "data.lua").as_posix()
    lua.execute(MINIMAL_NATIVE_FACTS)
    lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          -- Test-owned expected identities. Keep this independent from
          -- bootstrap's local selector declaration.
          TEST_COMPETING_PROVIDER_IDS = {
            "ExpandedProductivityResearch", "plates-n-circuit-productivity",
            "Science_packs_productivity", "bioflux-productivity", "fish-productivity",
            "crafting-efficiency-2", "ProductivityResearch"
          }

          function install_modules(caps_enabled, repair_enabled, scripted_active, native_credit_active)
            CAP_ACTIVE = caps_enabled == true
            REPAIR_ACTIVE = repair_enabled == true
            SCRIPTED_ACTIVE = scripted_active == true
            NATIVE_CREDIT_ACTIVE = native_credit_active == true
            credit_calls = {}
            module_credit_calls = {}
            cannon_credit_calls = {}
            gun_credit_calls = {}
            configuration_order = {}
            package.preload["platform.target"] = function()
              local target = dofile(player_root .. "/platform/target.lua")
              target.recipe_productivity = NATIVE_CREDIT_ACTIVE
              return target
            end
            package.preload["runtime.native_credits"] = function()
              local module = {}
              module.preflight_family_transition = function(event)
                local plan = {family_snapshot = true}
                credit_calls.family_event = event
                credit_calls.family_plan = plan
                return plan
              end
              for _, name in ipairs({"preflight_force_created", "preflight_force_reset",
                  "preflight_forces_merged", "preflight_technology_effects_reset"}) do
                local preflight = name
                module[preflight] = function(event)
                  local plan = {boundary_snapshot = preflight}
                  credit_calls[preflight] = event
                  credit_calls[preflight .. "_plan"] = plan
                  return plan
                end
              end
              module.needs_research_events = function() return false end
              module.on_research_finished = function() return false end
              module.on_research_cancelled = function() return false end
              module.preflight_legacy_preference_transition = function(event, provider_relevant)
                credit_calls.preflight = (credit_calls.preflight or 0) + 1
                credit_calls.last_preflight_event = event
                credit_calls.last_preflight_provider_relevant = provider_relevant
                table.insert(configuration_order, "native-credit-preflight")
                if CREDIT_PREFLIGHT_ERROR then error(CREDIT_PREFLIGHT_ERROR) end
              end
              for _, name in ipairs({"on_init", "on_configuration_changed", "on_load",
                  "on_force_created", "on_force_reset", "on_forces_merged", "on_technology_effects_reset"}) do
                local callback = name
                module[callback] = function(event, plan)
                  credit_calls[callback] = (credit_calls[callback] or 0) + 1
                  credit_calls.last_event = event
                  if callback == "on_configuration_changed" then
                    credit_calls.applied_family_plan = plan
                    table.insert(configuration_order, "native-credit-reconcile")
                  end
                end
              end
              return module
            end
            package.preload["runtime.legacy_module_credits"] = function()
              return {
                preflight = function(event)
                  module_credit_calls.preflight = event
                  table.insert(configuration_order, "module-credit-preflight")
                  if MODULE_CREDIT_PREFLIGHT_ERROR then error(MODULE_CREDIT_PREFLIGHT_ERROR) end
                  return {snapshot = true}
                end,
                apply = function(plan)
                  module_credit_calls.plan = plan
                  table.insert(configuration_order, "module-credit-apply")
                end,
                on_technology_effects_reset = function(event)
                  module_credit_calls.reset = event
                end
              }
            end
            package.preload["runtime.legacy_cannon_credits"] = function()
              return {
                preflight = function(event)
                  cannon_credit_calls.preflight = event
                  table.insert(configuration_order, "cannon-credit-preflight")
                  if CANNON_CREDIT_PREFLIGHT_ERROR then error(CANNON_CREDIT_PREFLIGHT_ERROR) end
                  return {snapshot = true}
                end,
                apply = function(plan)
                  cannon_credit_calls.plan = plan
                  table.insert(configuration_order, "cannon-credit-apply")
                end,
                on_technology_effects_reset = function(event)
                  cannon_credit_calls.reset = event
                end
              }
            end
            package.preload["runtime.native_gun_credits"] = function()
              local module = {
                set_retirement_policy = function(policy) gun_credit_calls.retirement_policy=policy end,
                has_retired_work = function() return false end,
                on_research_queue_event = function(event) gun_credit_calls.queue_event=event end,
                preflight = function(event)
                  gun_credit_calls.preflight = event
                  table.insert(configuration_order, "gun-credit-preflight")
                  if GUN_CREDIT_PREFLIGHT_ERROR then error(GUN_CREDIT_PREFLIGHT_ERROR) end
                  return {gun_snapshot=true}
                end,
                needs_research_events = function() return GUN_PENDING == true end,
                on_research_finished = function(event)
                  gun_credit_calls.finished=event;GUN_PENDING=false;return true
                end,
                on_research_cancelled = function(event)
                  gun_credit_calls.cancelled=event;GUN_PENDING=false;return true
                end,
              }
              for _,name in ipairs({"on_init","on_configuration_changed","on_load",
                  "on_force_created","on_force_reset","on_forces_merged","on_technology_effects_reset"}) do
                local callback=name
                module[callback]=function(event,plan)
                  gun_credit_calls[callback]=(gun_credit_calls[callback] or 0)+1
                  if callback=="on_configuration_changed" then gun_credit_calls.plan=plan end
                end
              end
              return module
            end
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
                set_retired_work_observer = function(observer) lifecycle_calls.retired_work_observer=observer end,
                reconcile_retired_paid_work = function() end,
                preflight = function(configuration_changed)
                  local plan = {configuration_changed=configuration_changed}
                  lifecycle_calls.cap_plan = plan
                  return plan
                end,
                preflight_worker_storage_split_caps = function(plan)
                  lifecycle_calls.worker_cap_plan = plan
                  return nil
                end,
                apply_worker_storage_split_caps = function(plan)
                  assert(plan == nil, "unexpected cap plan in lifecycle stub")
                end,
                cap_limits = function(force)
                  lifecycle_calls.cap_force = force
                  return { ["recipe-prod-research_gears-1"] = 2 }
                end,
                caps_active = function() return CAP_ACTIVE end,
                on_init = function(plan)
                  assert(plan==lifecycle_calls.cap_plan and plan.configuration_changed==false)
                  lifecycle_calls.init = (lifecycle_calls.init or 0) + 1
                end,
                on_configuration_changed = function(event,plan)
                  assert(plan==lifecycle_calls.cap_plan and plan.configuration_changed==true)
                  lifecycle_calls.configuration = event
                  table.insert(configuration_order, "lifecycle")
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
              module.native_refresh_ticks = 1
              module.native_subscription_needs = function() return false, false end
              module.set_cap_provider = function(provider) library_calls.provider = provider end
              module.set_discovery_visibility_provider = function(provider) library_calls.visibility_provider = provider end
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
              module.on_gui_checked_state_changed = function(event) library_calls.checked = event end
              module.on_gui_click = function(event) library_calls.click = event end
              module.on_gui_location_changed = function(event) library_calls.location = event end
              module.on_player_display_changed = function(event) library_calls.display_changed = event end
              module.on_gui_closed = function(event) library_calls.closed = event end
              module.on_pre_player_removed = function(event) library_calls.pre_removed = event end
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
              on_init = function(callback) handlers.init = function(event) install_worker_recovery_facts();return callback(event) end end,
              on_configuration_changed = function(callback) handlers.configuration = function(event) install_worker_recovery_facts();return callback(event) end end,
              on_load = function(callback) handlers.load = callback end,
              on_event = function(id, callback, filters)
                handlers.events[id] = callback and function(event)
                  local force=event and rawget(event,"force")
                  if not force and event and type(event.research)=="table" then force=rawget(event.research,"force") end
                  if force then install_worker_recovery_facts({force}) end
                  return callback(event)
                end or nil
                handlers.filters[id] = filters
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
              on_gui_location_changed = 11, on_gui_closed = 12, on_pre_player_removed = 22,
              on_player_removed = 13,
              on_entity_damaged = 14, on_string_translated = 15,
              on_player_locale_changed = 16, on_player_changed_force = 17,
              on_player_joined_game = 18, on_research_reversed = 19,
              on_technology_effects_reset = 20, on_gui_selected_tab_changed = 21, on_tick = 23,
              on_gui_checked_state_changed = 24, on_forces_merging = 26, on_research_queued = 27
            }}
            known_technology = {valid = true, name = "recipe-prod-research_gears-1"}
            player = {valid = true, index = 1, frame = {valid = true},
              force = {technologies = {[known_technology.name] = known_technology}}}
            game = {get_player = function(index) return index == 1 and player or nil end}
          end

          function load_control()
            install_worker_recovery_facts()
            package.loaded["control"] = nil
            package.loaded["runtime.bootstrap"] = nil
            package.loaded["runtime.worker_robot_storage"] = nil
            package.loaded["platform.target"] = nil
            package.loaded["runtime.native_credits"] = nil
            package.loaded["runtime.legacy_module_credits"] = nil
            package.loaded["runtime.legacy_cannon_credits"] = nil
            package.loaded["runtime.native_gun_credits"] = nil
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

    return lua
