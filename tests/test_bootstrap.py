"""Pure Lua 5.2 controls for explicit MIR5 control/data-stage composition.

These tests exercise only registration and callback routing with host doubles.
They are not Factorio engine, GUI, menu, save, or gameplay evidence.
"""
import argparse
from pathlib import Path
import sys
import unittest
from bootstrap_control_world import build_bootstrap_control_world, install_bootstrap_control_world
from native_credit_world import build_native_credit_runtime_world, install_native_family_paid_world

ROOT = Path(__file__).resolve().parents[1]


class BootstrapTests(unittest.TestCase):
    def setUp(self, lua=None):
        self.lua = (
            install_bootstrap_control_world(lua, source_root=ROOT / "source")
            if lua is not None
            else build_bootstrap_control_world(LuaRuntime, source_root=ROOT / "source")
        )

    def test_se_scripted_policy_preflights_first_and_applies_after_existing_reconciliation(self):
        for mode in ("success", "observe", "policy-refusal", "other-preflight-refusal"):
            with self.subTest(mode=mode):
                self.setUp()
                self.lua.globals().policy_mode = mode
                self.lua.execute('''
                  install_modules(false,false,false,true)
                  package.preload["platform.target"]=function()return {id="f200",recipe_productivity=true}end
                  install_runtime(nil,{["space-exploration"]="0.7.57"})
                  local cap=require("runtime.lifecycle");local original=cap.preflight
                  cap.preflight=function(...)
                    assert(policy_preflight_seen==1)
                    if policy_mode=="other-preflight-refusal"then error("other preflight refused")end
                    return original(...)
                  end
                  package.preload["runtime.lifecycle"]=function()return cap end
                  package.preload["runtime.space_exploration_system_force"]=function()return {
                    preflight=function(event)
                      assert(event.marker=="SE-policy"and library_calls.configuration==nil)
                      policy_preflight_seen=(policy_preflight_seen or 0)+1
                      if policy_mode=="policy-refusal"then error("SE policy refused")end
                      if policy_mode~="observe"then return "SE-plan"end
                    end,
                    apply=function(plan)
                      assert(library_calls.configuration.marker=="SE-policy")
                      assert(plan==(policy_mode~="observe"and "SE-plan"or nil))
                      policy_apply_seen=(policy_apply_seen or 0)+1
                      return plan~=nil
                    end,
                    observe=function()
                      assert(policy_apply_seen==1 and library_calls.configuration.marker=="SE-policy")
                      policy_observe_seen=(policy_observe_seen or 0)+1
                    end}end
                  load_control()
                  local ok,message=pcall(handlers.configuration,{marker="SE-policy",mod_changes={}})
                  assert(policy_preflight_seen==1)
                  if policy_mode=="success" or policy_mode=="observe"then
                    assert(ok,message);assert(policy_apply_seen==1)
                    assert(policy_observe_seen==(policy_mode=="observe"and 1 or nil))
                  else assert(not ok and tostring(message):find("refused",1,true))
                    assert(policy_apply_seen==nil and policy_observe_seen==nil and library_calls.configuration==nil)end
                ''')

    def test_se_scripted_policy_body_is_not_imported_for_an_inactive_target_or_provider(self):
        for target_id, provider in (("f210", "0.7.57"), ("f200", "0.7.58"), ("f200", None)):
            with self.subTest(target_id=target_id, provider=provider):
                self.setUp()
                self.lua.globals().selected_target = target_id
                self.lua.globals().selected_provider = provider
                self.lua.execute('''
                  install_modules(false)
                  package.preload["platform.target"]=function()return {id=selected_target,recipe_productivity=false}end
                  local active={};active["space-exploration"]=selected_provider
                  install_runtime(nil,active)
                  package.preload["runtime.space_exploration_system_force"]=function()error("inactive body import")end
                  load_control()
                  local old_force={name="conquest"};storage.mir_se_conquest_policy_force=old_force
                  handlers.configuration({mod_changes={}})
                  assert(storage.mir_se_conquest_policy_force==(selected_target=="f210"and old_force or nil))
                ''')

    def test_actual_bootstrap_keeps_gate_only_configuration_after_legacy_commit(self):
        # Routing only: the complete worker/history controls own native-frame
        # validation. This independent order must not delegate a flag-only plan.
        for preflight_error in (False, True):
            with self.subTest(preflight_error=preflight_error):
                self.setUp()
                self.lua.globals().gate_preflight_error = preflight_error
                self.lua.execute('''
                  install_modules(false);install_runtime()
                  local catalogue=require("runtime.catalogue")
                  catalogue.worker_default_split=function()return true end
                  local worker=require("runtime.worker_robot_storage")
                  local lifecycle=require("runtime.lifecycle")
                  local plan={kind="default-native-provider-gate-settle",changed=true}
                  local legacy={kind="unchanged-prepared-quota"};local order={}
                  worker.default_owner_preflight=function(event,route,split)
                    assert(split and route==nil and event.marker=="gate-only")
                    order[#order+1]="owner-preflight"
                    if gate_preflight_error then error("invalid paid H frame")end
                    return plan
                  end
                  worker.preflight=function(event,route,delegated)
                    assert(delegated==nil);order[#order+1]="legacy-preflight";return legacy
                  end
                  worker.apply=function(value)
                    assert(value==legacy);order[#order+1]="legacy-commit"
                  end
                  worker.default_owner_apply=function(value)
                    assert(value==plan and order[#order]=="legacy-commit")
                    order[#order+1]="gate-only-apply"
                  end
                  lifecycle.preflight_worker_storage_split_caps=function(value)
                    assert(value==plan);order[#order+1]="cap-preflight";return nil
                  end
                  lifecycle.apply_worker_storage_split_caps=function(value)
                    assert(value==nil and order[#order]=="gate-only-apply")
                    order[#order+1]="cap-noop"
                  end
                  package.preload["runtime.worker_robot_storage"]=function()return worker end
                  package.preload["runtime.lifecycle"]=function()return lifecycle end
                  load_control()
                  local ok,message=pcall(handlers.configuration,{marker="gate-only",mod_startup_settings_changed=true,mod_changes={}})
                  if gate_preflight_error then
                    assert(not ok and tostring(message):find("invalid paid H frame",1,true))
                    assert(#order==1 and lifecycle_calls.configuration==nil)
                  else
                    assert(ok,message)
                    assert(table.concat(order,",")=="owner-preflight,legacy-preflight,cap-preflight,legacy-commit,gate-only-apply,cap-noop",table.concat(order,","))
                    assert(lifecycle_calls.configuration.marker=="gate-only"and library_calls.configuration.marker=="gate-only")
                  end
                ''')

    def test_cap_admission_preflight_failure_precedes_other_lifecycle_writers(self):
        for callback in ("init", "configuration"):
            with self.subTest(callback=callback):
                self.setUp()
                self.lua.globals().fault_callback = callback
                self.lua.execute('''
                  install_modules(true,true,true,true)
                  install_runtime(nil,{["space-age"]="2.1.23"});load_control()
                  local cause={boundary="cap-preflight"}
                  require("runtime.lifecycle").preflight=function()error(cause)end
                  local ok,reason=pcall(handlers[fault_callback],{})
                  assert(not ok and reason==cause,"bootstrap lost the original cap admission failure")
                  assert(lifecycle_calls.init==nil and lifecycle_calls.configuration==nil
                    and credit_calls.on_init==nil and credit_calls.on_configuration_changed==nil
                    and library_calls.init==nil and library_calls.configuration==nil
                    and scripted_calls.init==nil and scripted_calls.configuration==nil
                    and #configuration_order==0,
                    "cap admission ran after another reconciler wrote")
                ''')

    def test_required_cap_preflight_export_fails_before_callback_registration(self):
        for export in (None, False, "wrong"):
            with self.subTest(export=export):
                self.setUp()
                self.lua.globals().bad_cap_preflight = export
                self.lua.execute('''
                  install_modules(false,false,false,false);install_runtime()
                  local original=package.preload["runtime.lifecycle"]
                  package.preload["runtime.lifecycle"]=function()
                    local lifecycle=original();lifecycle.preflight=bad_cap_preflight;return lifecycle
                  end
                  local ok,reason=pcall(load_control)
                  assert(not ok and tostring(reason):find("caps requires callable preflight",1,true))
                  assert(handlers.init==nil and handlers.configuration==nil
                    and next(handlers.events)==nil,"broken cap composition registered handlers")
                ''')

    def test_gun_credit_preflight_runs_before_every_configuration_writer(self):
        self.lua.execute('''
          install_modules(false,false,false,true)
          install_runtime(nil,{["space-age"]="2.0.0"});load_control()
          GUN_CREDIT_PREFLIGHT_ERROR="gun paid mask unknown"
          local ok,message=pcall(handlers.configuration,{marker="original-event"})
          assert(not ok and tostring(message):find("gun paid mask unknown",1,true))
          assert(lifecycle_calls.configuration==nil and credit_calls.on_configuration_changed==nil)
          assert(module_credit_calls.plan==nil and cannon_credit_calls.plan==nil)
          GUN_CREDIT_PREFLIGHT_ERROR=nil
          handlers.configuration({marker="original-event"})
          assert(configuration_order[4]=="gun-credit-preflight")
          assert(gun_credit_calls.plan.gun_snapshot and gun_credit_calls.on_configuration_changed==1)
        ''')

    def test_gun_pending_callbacks_reconstruct_and_release_without_native_recurring_work(self):
        self.lua.execute('''
          install_modules(false,false,false,true)
          install_runtime(nil,{["space-age"]="2.0.0"});load_control()
          handlers.init()
          assert(handlers.events[defines.events.on_research_finished]==nil)
          assert(handlers.events[defines.events.on_research_cancelled]==nil)
          GUN_PENDING=true;handlers.load()
          assert(type(handlers.events[defines.events.on_research_finished])=="function")
          assert(type(handlers.events[defines.events.on_research_cancelled])=="function")
          assert(type(handlers.events[defines.events.on_research_started])=="function")
          assert(type(handlers.events[defines.events.on_research_queued])=="function")
          assert(type(gun_credit_calls.retirement_policy)=="function")
          assert(type(lifecycle_calls.retired_work_observer)=="function")
          local event={research=known_technology}
          handlers.events[defines.events.on_research_queued](event)
          assert(gun_credit_calls.queue_event==event)
          handlers.events[defines.events.on_research_finished](event)
          assert(gun_credit_calls.finished==event)
          assert(handlers.events[defines.events.on_research_finished]==nil)
          assert(handlers.events[defines.events.on_research_cancelled]==nil)
          assert(handlers.events[defines.events.on_research_started]==nil)
          assert(handlers.events[defines.events.on_research_queued]==nil)
          assert(next(handlers.nth)==nil and handlers.events[defines.events.on_tick]==nil)
        ''')

    def test_gun_lifecycle_is_absent_from_base_only_control(self):
        self.lua.execute('''
          install_modules(false,false,false,true);install_runtime();load_control()
          handlers.init();handlers.configuration({});handlers.load()
          assert(next(gun_credit_calls)==nil and package.loaded["runtime.native_gun_credits"]==nil)
        ''')

    def test_control_composes_lifecycle_library_api_legacy_interface_and_command(self):
        self.lua.execute('''
          install_modules(true); install_runtime()
          defines.events.on_player_display_scale_changed = 1001
          defines.events.on_player_display_resolution_changed = 1002
          load_control()
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
          assert(type(handlers.events[defines.events.on_forces_merging]) == "function",
            "worker pre-merge capture was not bound alongside the post-merge lifecycle")
          handlers.events[defines.events.on_forces_merging]({})
          assert(handlers.events[1] == nil or handlers.events[1] ~= handlers.events[7])
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
          assert(type(handlers.events[21]) == "function")
          assert(type(handlers.events[22]) == "function")
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
          assert(handlers.events[14] == nil and handlers.nth[60] == nil and handlers.nth[61] == nil and storage.mir == nil)
          handlers.events[7]({player_index = 1, prototype_name = "mir-research-browser"})
          for _, id in ipairs({8, 21, 9, 10, 11}) do
            handlers.events[id]({player_index = 1, element = {name = "mir_library_control"}})
          end
          handlers.events[defines.events.on_player_display_scale_changed]({player_index = 1, old_scale = 1})
          assert(library_calls.display_changed.player_index == 1 and library_calls.display_changed.old_scale == 1)
          handlers.events[defines.events.on_player_display_resolution_changed]({player_index = 1,
            old_resolution = {width = 1920, height = 1080}})
          assert(library_calls.display_changed.player_index == 1 and library_calls.display_changed.old_resolution.width == 1920)
          handlers.events[12]({player_index = 1, element = {name = "mir_research_browser"}})
          handlers.events[22]({player_index = 1})
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
            and library_calls.pre_removed.player_index == 1 and library_calls.removed.player_index == 1)
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
          assert(library_calls.open.player == player and library_calls.open.options.search == "gear"
            and library_calls.open.options.query == nil,
            "legacy search must reach the Library without the bridge choosing a query field")
          assert(library_calls.open.options.family == "mir"
            and library_calls.open.options.selected == known_technology.name
            and library_calls.open.options.status == 4 and library_calls.open.options.mode == 3
            and library_calls.open.options.sort == "name-desc"
            and library_calls.open.options.page == 7 and library_calls.open.options.hidden == hidden)
          assert(browser.open(1, {tab = "settings", settings_scope = "options", search = "repair"}))
          assert(library_calls.open.options.tab == "settings"
            and library_calls.open.options.settings_scope == "options"
            and library_calls.open.options.search == "repair" and library_calls.open.options.query == nil,
            "legacy Settings search and scope must reach the Library together")
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

    def test_missing_or_invalid_research_does_not_enter_runtime_consumers(self):
        self.lua.execute('''
          install_modules(true, false, true, true)
          install_runtime(nil, {['space-age'] = '2.1.23'})
          load_control()
          local entered = 0
          local function invalid_dispatch(event)
            entered = entered + 1
            -- A real invalid LuaTechnology permits valid, but accessing its
            -- other properties can fail. The original dispatcher rejected it
            -- before any feature callback; consumers must never be entered.
            if event and event.research then return event.research.name end
          end
          for _, name in ipairs({'runtime.lifecycle', 'runtime.scripted_effects',
              'runtime.native_credits'}) do
            local module = package.loaded[name]
            module.on_research_finished = invalid_dispatch
            module.on_research_reversed = invalid_dispatch
            module.on_research_started = invalid_dispatch
          end
          local invalid = setmetatable({valid = false}, {
            __index = function(_, key) error('invalid research property: ' .. key) end
          })
          for _, id in ipairs({4, 19, 5}) do
            local callback = assert(handlers.events[id])
            callback(nil)
            callback({})
            callback({research = invalid})
          end
          assert(entered == 0, 'missing/invalid research reached a runtime consumer')
        ''')

    def test_queued_research_guard_preserves_valid_library_and_discovery_dispatch(self):
        self.lua.execute('''
          for _, discovery in ipairs({false, true}) do
            install_modules(true)
            install_runtime(nil, discovery and {discovery_tree = '1.0.12'} or {})
            defines.events.on_research_queued = 25
            load_control()
            local browser = require('runtime.library')
            browser.native_subscription_needs = function() return true, false end
            local queued = 0
            browser.on_native_state_changed = function(event)
              assert(event.research == known_technology)
              queued = queued + 1
            end
            local discovered = 0
            require('runtime.lifecycle').on_discovery_tree_queue_changed = function(event)
              assert(event.research == known_technology)
              discovered = discovered + 1
            end
            handlers.init()
            local invalid = setmetatable({valid = false}, {
              __index = function(_, key) error('invalid queued research property: ' .. key) end
            })
            local callback = assert(handlers.events[25])
            callback(nil)
            callback({})
            callback({research = invalid})
            assert(queued == 0 and discovered == 0)
            callback({research = known_technology})
            assert(queued == 1 and discovered == (discovery and 1 or 0),
              'valid queued research lost its existing view/discovery route')
          end
        ''')

    def test_report_checkbox_event_has_one_bootstrap_registration_owner(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          local event={player_index=1,element={valid=true,name="mir_library_report_settings",state=true}}
          assert(type(handlers.events[24])=="function")
          handlers.events[24](event)
          assert(library_calls.checked==event)
        ''')

    def test_unlimited_control_omits_only_cap_event_callbacks(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          for id = 1, 3 do assert(type(handlers.events[id]) == "function") end
          for id = 4, 6 do assert(handlers.events[id] == nil) end
          assert(handlers.events[19] == nil and handlers.events[20] == nil)
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
          for id = 15, 18 do assert(type(handlers.events[id]) == "function") end
        ''')

    def test_foreign_gui_events_do_not_query_library_subscriptions(self):
        self.lua.execute('''
          install_modules(false); install_runtime(); load_control()
          local browser = require("runtime.library")
          local subscription_reads = 0
          browser.subscription_needs = function() subscription_reads = subscription_reads + 1; return false end
          browser.native_subscription_needs = function()
            subscription_reads = subscription_reads + 1
            return false, false
          end
          local events = defines.events
          local gui_events = {events.on_gui_text_changed, events.on_gui_selected_tab_changed,
            events.on_gui_selection_state_changed, events.on_gui_checked_state_changed,
            events.on_gui_click, events.on_gui_location_changed, events.on_gui_closed}
          for _, id in ipairs(gui_events) do
            local callback = assert(handlers.events[id])
            callback({player_index = 1, element = {valid = true, name = "another_mod_control"}})
            callback({player_index = 1, element = {valid = false, name = "mir_library_control"}})
            callback({player_index = 1})
          end
          handlers.events[events.on_lua_shortcut]({player_index = 1, prototype_name = "another-mod-shortcut"})
          assert(subscription_reads == 0, "foreign GUI input read Library subscriptions")
          assert(library_calls.click == nil and library_calls.shortcut == nil)
          for _, id in ipairs(gui_events) do
            handlers.events[id]({player_index = 1, element = {valid = true, name = "mir_library_control"}})
          end
          handlers.events[events.on_lua_shortcut]({player_index = 1, prototype_name = "mir-research-browser"})
          assert(subscription_reads == 2 * (#gui_events + 1), "owned GUI input lost subscription reconciliation")
          assert(library_calls.click ~= nil and library_calls.shortcut ~= nil)
        ''')

    def test_settled_native_only_world_has_no_periodic_work_after_view_cycles_and_reload(self):
        self.lua.execute('''
          install_modules(false,false,false,false);install_runtime();load_control()
          local browser=require("runtime.library")
          local open,pending=false,false
          browser.native_subscription_needs=function()return open,pending end
          browser.on_gui_closed=function()open,pending=false,false end
          for cycle=1,100 do
            open,pending=true,true
            handlers.events[15]({player_index=1,id=cycle,translated=false})
            assert(type(handlers.nth[1])=="function")
            handlers.events[12]({player_index=1, element={name="mir_research_browser"}})
            assert(handlers.nth[1]==nil and handlers.nth[60]==nil and handlers.nth[61]==nil)
          end
          game=setmetatable({}, {__index=function()error("idle/reload world access")end,
            __newindex=function()error("idle/reload world write")end})
          assert(handlers.events[defines.events.on_tick]==nil, "settled server has an ordinary on_tick handler")
          handlers.load()
          assert(handlers.events[defines.events.on_tick]==nil, "on_load added an ordinary on_tick handler")
          assert(next(handlers.nth)==nil)
          for _,id in ipairs({4,5,6,19,20})do assert(handlers.events[id]==nil)end
          assert(storage.mir==nil)
        ''')

    def test_native_credit_lifecycle_survives_provider_absence_without_research_callbacks(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime();
          package.preload["platform.target"] = function()
            return {id="f200", recipe_productivity=true}
          end
          load_control()
          handlers.init(); handlers.configuration({mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'}}}); handlers.load()
          assert(credit_calls.on_init == 1 and credit_calls.preflight == 1 and credit_calls.on_configuration_changed == 1
            and credit_calls.on_load == 1)
          assert(configuration_order[1] == "native-credit-preflight"
            and configuration_order[2] == "module-credit-preflight"
            and configuration_order[3] == "cannon-credit-preflight"
            and configuration_order[4] == "lifecycle"
            and configuration_order[5] == "native-credit-reconcile"
            and configuration_order[6] == "module-credit-apply"
            and configuration_order[7] == "cannon-credit-apply")
          assert(credit_calls.last_preflight_provider_relevant == false,
            "ordinary Base upgrade was marked as a competing-provider transition")
          for _, id in ipairs({1, 2, 3, 20}) do assert(type(handlers.events[id]) == "function") end
          for _, id in ipairs({4, 5, 6, 19}) do assert(handlers.events[id] == nil) end
          require("runtime.library").native_subscription_needs=function()
            error("force lifecycle scanned saved Library views while closed")
          end
          for _, id in ipairs({1, 2, 3, 20}) do handlers.events[id]({force=player.force}) end
          assert(credit_calls.on_force_created == 1 and credit_calls.on_force_reset == 1
            and credit_calls.on_forces_merged == 1 and credit_calls.on_technology_effects_reset == 1)
          assert(lifecycle_calls.force_created.force == player.force
            and lifecycle_calls.force_reset.force == player.force
            and lifecycle_calls.forces_merged.force == player.force,
            "registered force boundaries skipped retained cap-ownership cleanup")
          assert(lifecycle_calls.effects_reset.force == player.force,
            "unlimited effects reset skipped authored-prototype disablement")
          assert(storage.mir_native_credits == nil and handlers.nth[60] == nil and handlers.nth[61] == nil)
          install_modules(false, false, false, false); remote.interfaces = {}; load_control()
          for _, id in ipairs({1, 2, 3}) do assert(type(handlers.events[id]) == "function") end
          for _, id in ipairs({4, 5, 6, 19, 20}) do assert(handlers.events[id] == nil) end
        ''')

    def test_family_credit_preflight_refuses_before_any_configuration_write(self):
        self.lua.execute('''
          install_modules(false,false,false,true);install_runtime();load_control()
          require("runtime.native_credits").preflight_family_transition=function(event)
            assert(event.token==42);error("unknown first paid recipe mask")
          end
          local ok,message=pcall(handlers.configuration,{token=42,mod_changes={}})
          assert(not ok and tostring(message):find("unknown first paid recipe mask",1,true))
          assert(lifecycle_calls.configuration==nil and credit_calls.on_configuration_changed==nil
            and library_calls.configuration==nil and module_credit_calls.preflight==nil
            and cannon_credit_calls.preflight==nil)
        ''')

    def test_native_credit_boundary_preflights_precede_each_lifecycle_writer(self):
        cases = (
            ("preflight_force_created", "on_force_created", 1, "{force=player.force}"),
            ("preflight_force_reset", "on_force_reset", 2, "{force=player.force}"),
            ("preflight_forces_merged", "on_forces_merged", 3,
             "{source_index=17,destination=player.force}"),
            ("preflight_technology_effects_reset", "on_technology_effects_reset", 20,
             "{force=player.force}"),
        )
        for preflight, callback, event_id, event in cases:
            with self.subTest(preflight=preflight):
                self.setUp()
                self.lua.globals().boundary_preflight = preflight
                self.lua.globals().boundary_callback = callback
                self.lua.globals().boundary_event_id = event_id
                self.lua.execute(f'''
                  install_modules(false,false,false,true);install_runtime();load_control()
                  local module=require("runtime.native_credits")
                  local cause={{boundary=boundary_preflight}}
                  module[boundary_preflight]=function(actual)
                    assert(actual.force==player.force or actual.destination==player.force)
                    error(cause)
                  end
                  local ok,reason=pcall(handlers.events[boundary_event_id],{event})
                  assert(not ok and reason==cause,"boundary preflight lost its original failure")
                  assert(credit_calls[boundary_callback]==nil
                    and lifecycle_calls.force_created==nil and lifecycle_calls.force_reset==nil
                    and lifecycle_calls.forces_merged==nil and lifecycle_calls.effects_reset==nil
                    and library_calls.force==nil,
                    "native boundary preflight ran after a lifecycle writer")
                ''')

    def test_native_credit_required_exports_refuse_before_bootstrap_registration(self):
        for target_id in ("f200", "f210"):
            for export in ("preflight_family_transition", "preflight_force_created",
                           "preflight_force_reset", "preflight_forces_merged",
                           "preflight_technology_effects_reset", "needs_research_events",
                           "on_research_finished", "on_research_cancelled"):
                for opponent in ("missing", "false", "table"):
                    with self.subTest(target=target_id, export=export, opponent=opponent):
                        self.setUp()
                        self.lua.globals().target_id = target_id
                        self.lua.globals().export_name = export
                        self.lua.globals().opponent = opponent
                        self.lua.execute(r'''
                          install_modules(false,false,false,true);install_runtime()
                          local credit_factory=package.preload["runtime.native_credits"]
                          local supplied=credit_factory()
                          if opponent=="missing" then supplied[export_name]=nil
                          elseif opponent=="false" then supplied[export_name]=false
                          else supplied[export_name]={} end
                          assert(type(supplied[export_name])~="function")
                          package.preload["runtime.native_credits"]=function()return supplied end
                          local target_factory=package.preload["platform.target"]
                          package.preload["platform.target"]=function()
                            local target=target_factory();target.id=target_id;return target
                          end
                          local ok,message=pcall(load_control)
                          assert(not ok and tostring(message):find(
                            "MIR runtime native credits requires callable "..export_name,1,true),
                            "required credit export was treated as optional: "..export_name)
                          assert(next(remote.interfaces)==nil and next(commands.registered)==nil
                            and handlers.init==nil and handlers.configuration==nil and handlers.load==nil
                            and next(handlers.events)==nil and next(handlers.nth)==nil,
                            "invalid credit interface registered callbacks or commands")
                          assert(next(lifecycle_calls)==nil and next(library_calls)==nil
                            and next(credit_calls)==nil and next(module_credit_calls)==nil
                            and next(cannon_credit_calls)==nil and next(gun_credit_calls)==nil,
                            "invalid credit interface reached a lifecycle writer")
                        ''')

    def test_family_credit_plan_is_forwarded_without_recomputing_or_dropping_it(self):
        self.lua.execute(r'''
          install_modules(false,false,false,true);install_runtime();load_control()
          local event={mod_changes={}}
          handlers.configuration(event)
          assert(credit_calls.family_event==event and credit_calls.family_plan.family_snapshot)
          assert(credit_calls.applied_family_plan==credit_calls.family_plan,
            "configuration discarded the admitted family plan")
        ''')

    def test_inactive_native_credit_subsystem_does_not_require_or_load_its_interface(self):
        for target_id in ("f200", "f210", "f018"):
            with self.subTest(target=target_id):
                self.setUp()
                self.lua.globals().target_id = target_id
                self.lua.execute(r'''
                  install_modules(false,false,false,false);install_runtime()
                  package.preload["runtime.native_credits"]=function()
                    error("inactive credit module was imported")
                  end
                  local target_factory=package.preload["platform.target"]
                  package.preload["platform.target"]=function()
                    local target=target_factory();target.id=target_id;return target
                  end
                  load_control();handlers.init();handlers.configuration({mod_changes={}});handlers.load()
                  assert(package.loaded["runtime.native_credits"]==nil and next(credit_calls)==nil)
                  assert(lifecycle_calls.configuration~=nil and library_calls.configuration~=nil)
                ''')

    def test_real_same_engine_unknown_paid_mask_refuses_before_configuration_writes(self):
        import test_native_family_paid_credits as paid_fixture
        for opponent in ("mir-fixture-observer", "ExpandedProductivityResearch", "space-age"):
            with self.subTest(opponent=opponent):
                case = paid_fixture.NativeFamilyPaidCreditsTests()
                case.lua = build_native_credit_runtime_world(
                    LuaRuntime, target="f210", source_root=ROOT / "source"
                )
                install_native_family_paid_world(case.lua, target="f210")
                case._same_engine_unknown_paid_mask(opponent)
                self.setUp(case.lua)
                self.lua.execute('''
                  local real_credits=native_credits
                  install_modules(true,false,true,true);install_runtime(nil,BASE_ACTIVE);game.forces={}
                  package.preload["runtime.native_credits"]=function()return real_credits end
                  load_control()
                  local registrations=0
                  script.on_event=function()registrations=registrations+1 end
                  script.on_nth_tick=function()registrations=registrations+1 end
                  assert_unknown_mask_refuses(handlers.configuration)
                  assert(lifecycle_calls.configuration==nil and library_calls.configuration==nil
                    and module_credit_calls.preflight==nil and cannon_credit_calls.preflight==nil
                    and scripted_calls.configuration==nil and registrations==0,
                    "bootstrap wrote cap/force/control state before real credit refusal")
                ''')

    def test_paid_mask_bootstrap_does_not_select_paid_testcase_setup(self):
        import test_native_family_paid_credits as paid_fixture

        missing_runtime = object()
        original_runtime = getattr(paid_fixture, "LuaRuntime", missing_runtime)
        original_setup = paid_fixture.NativeFamilyPaidCreditsTests.setUp

        def forbidden_setup(_case):
            raise AssertionError("bootstrap control selected paid TestCase setup")

        paid_fixture.NativeFamilyPaidCreditsTests.setUp = forbidden_setup
        try:
            self.test_real_same_engine_unknown_paid_mask_refuses_before_configuration_writes()
        finally:
            paid_fixture.NativeFamilyPaidCreditsTests.setUp = original_setup
            if original_runtime is missing_runtime:
                if hasattr(paid_fixture, "LuaRuntime"):
                    delattr(paid_fixture, "LuaRuntime")
            else:
                paid_fixture.LuaRuntime = original_runtime

    def test_only_pending_private_work_binds_completion_and_cancellation(self):
        self.lua.execute('''
          install_modules(false,false,false,true);install_runtime();load_control()
          local credits=require("runtime.native_credits");local pending=true;local seen
          credits.needs_research_events=function()return pending end
          credits.on_research_finished=function(event)seen=event;pending=false;return true end
          credits.on_research_cancelled=function(event)seen=event;pending=false;return true end
          handlers.init()
          assert(type(handlers.events[4])=="function" and type(handlers.events[6])=="function")
          assert(handlers.events[5]==nil and handlers.events[19]==nil)
          local done={research={name="private-old-work"}}
          handlers.events[4](done)
          assert(seen==done and handlers.events[4]==nil and handlers.events[6]==nil)
          pending=true;handlers.load()
          assert(type(handlers.events[4])=="function" and type(handlers.events[6])=="function")
          local cancelled={research={old=1}}
          handlers.events[6](cancelled)
          assert(seen==cancelled and handlers.events[4]==nil and handlers.events[6]==nil)
          assert(handlers.nth[60]==nil and handlers.nth[61]==nil)
        ''')

    def test_module_credit_preflight_precedes_all_configuration_writes(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime(); load_control()
          MODULE_CREDIT_PREFLIGHT_ERROR = "invalid legacy module shape"
          local event = {mod_changes={}}
          local ok, message = pcall(handlers.configuration, event)
          assert(not ok and tostring(message):find(MODULE_CREDIT_PREFLIGHT_ERROR, 1, true))
          assert(module_credit_calls.preflight == event and module_credit_calls.plan == nil)
          assert(next(cannon_credit_calls) == nil)
          assert(lifecycle_calls.configuration == nil and credit_calls.on_configuration_changed == nil
            and library_calls.configuration == nil)
        ''')

    def test_cannon_credit_preflight_precedes_all_configuration_writes(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime(); load_control()
          CANNON_CREDIT_PREFLIGHT_ERROR = "invalid legacy cannon shape"
          local event = {mod_changes={}}
          local ok, message = pcall(handlers.configuration, event)
          assert(not ok and tostring(message):find(CANNON_CREDIT_PREFLIGHT_ERROR, 1, true))
          assert(module_credit_calls.preflight == event and module_credit_calls.plan == nil)
          assert(cannon_credit_calls.preflight == event and cannon_credit_calls.plan == nil)
          assert(lifecycle_calls.configuration == nil and credit_calls.on_configuration_changed == nil
            and library_calls.configuration == nil)
        ''')

    def test_module_credit_has_no_init_load_research_or_old_target_work(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime(); load_control()
          handlers.init(); handlers.load()
          assert(next(module_credit_calls) == nil)
          assert(next(cannon_credit_calls) == nil)
          local event = {mod_changes={}}
          handlers.configuration(event)
          assert(module_credit_calls.preflight == event and module_credit_calls.plan.snapshot == true)
          assert(cannon_credit_calls.preflight == event and cannon_credit_calls.plan.snapshot == true)
          handlers.events[20]({force=player.force})
          assert(module_credit_calls.reset.force == player.force)
          assert(cannon_credit_calls.reset.force == player.force)
          handlers.events[3]({destination=player.force, source_index=2})
          assert(module_credit_calls.reset.force == player.force)
          assert(cannon_credit_calls.reset.force == player.force)
          for _, id in ipairs({4, 5, 6, 19}) do assert(handlers.events[id] == nil) end
          install_modules(false, false, false, false); remote.interfaces = {}; storage={}; load_control()
          handlers.init(); handlers.configuration(event); handlers.load()
          assert(next(module_credit_calls) == nil)
          assert(next(cannon_credit_calls) == nil)
        ''')

    def test_native_credit_preflight_marks_a_named_removed_provider_relevant(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime();
          package.preload["platform.target"] = function()
            return {id="f200", recipe_productivity=true}
          end
          load_control()
          for _, name in ipairs(TEST_COMPETING_PROVIDER_IDS) do
            handlers.configuration({mod_startup_settings_changed=true,
              mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'},
                [name]={old_version='1.0.0'}}})
            assert(credit_calls.last_preflight_provider_relevant == true,
              "removed named provider did not retain legacy-preflight relevance: " .. name)
          end
          handlers.configuration({mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20002', new_version='5.0.20000'},
              unrelated={old_version='1.0.0'}}})
          assert(credit_calls.last_preflight_provider_relevant == false,
            "unrelated removed mod was marked as competing-provider relevance")
        ''')

    def test_named_productivity_providers_activate_only_the_f200_adapter(self):
        self.lua.execute('''
          for _, name in ipairs(TEST_COMPETING_PROVIDER_IDS) do
            install_modules(false, false, false, true)
            install_runtime(nil, {[name]="1.0.0"})
            package.loaded["runtime.competing_productivity"] = nil
            package.preload["platform.target"] = function()
              return {id="f200", recipe_productivity=true}
            end
            local loads, configurations = 0, 0
            package.preload["runtime.competing_productivity"] = function()
              loads = loads + 1
              return {
                active = function() return false end,
                on_configuration_changed = function() configurations = configurations + 1 end,
                on_init = function() end,
                on_load = function() end,
                on_research_finished = function() end,
                on_research_reversed = function() end,
                on_technology_effects_reset = function() end,
                on_research_started = function() end,
                on_research_cancelled = function() end,
                on_force_created = function() end,
                on_force_reset = function() end,
                on_forces_merged = function() end
              }
            end
            load_control()
            assert(loads == 1, "F200 did not activate the named provider adapter: " .. name)
            handlers.configuration({mod_changes={}})
            assert(credit_calls.last_preflight_provider_relevant == true and configurations == 1,
              "F200 provider did not retain configuration relevance: " .. name)
          end

          install_modules(false, false, false, true)
          install_runtime(nil, {unrelated="1.0.0"})
          package.loaded["runtime.competing_productivity"] = nil
          package.preload["platform.target"] = function()
            return {id="f200", recipe_productivity=true}
          end
          package.preload["runtime.competing_productivity"] = function()
            error("absent F200 provider loaded the competing-productivity adapter")
          end
          load_control()
          handlers.configuration({mod_changes={}})
          assert(credit_calls.last_preflight_provider_relevant == false
              and package.loaded["runtime.competing_productivity"] == nil,
            "unrelated F200 profile acquired a competing provider")
        ''')

    def test_native_credit_preflight_stops_configuration_before_lifecycle_writes(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime();
          package.preload["platform.target"] = function()
            return {id="f200", recipe_productivity=true}
          end
          CREDIT_PREFLIGHT_ERROR = "ambiguous legacy preference"
          load_control()
          local ok, message = pcall(handlers.configuration, {mod_changes={}})
          assert(not ok and tostring(message):find("ambiguous legacy preference", 1, true))
          assert(credit_calls.preflight == 1 and lifecycle_calls.configuration == nil
            and credit_calls.on_configuration_changed == nil and library_calls.configuration == nil)
        ''')

    def test_f210_published_preference_transition_preflights_before_configuration_writes(self):
        self.lua.execute('''
          install_modules(false, false, false, true); install_runtime();
          package.preload["platform.target"] = function()
            return {id="f210", recipe_productivity=true}
          end
          CREDIT_PREFLIGHT_ERROR = "ambiguous legacy preference"
          load_control()

          local changed = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20003', new_version='5.0.21000'},
              ExpandedProductivityResearch={old_version='1.3.8'}}}
          local ok, message = pcall(handlers.configuration, changed)
          assert(not ok and tostring(message):find("ambiguous legacy preference", 1, true))
          assert(credit_calls.preflight == 1
            and credit_calls.last_preflight_event == changed
            and credit_calls.last_preflight_provider_relevant == true)
          assert(lifecycle_calls.configuration == nil and credit_calls.on_configuration_changed == nil
            and library_calls.configuration == nil,
            "F210 ambiguity preflight allowed configuration writes")

          CREDIT_PREFLIGHT_ERROR = nil
          local unchanged = {mod_startup_settings_changed=false,
            mod_changes={['more-infinite-research']={old_version='4.7.20003', new_version='5.0.21000'},
              ExpandedProductivityResearch={old_version='1.3.8'}}}
          assert(pcall(handlers.configuration, unchanged))
          assert(credit_calls.preflight == 2 and credit_calls.last_preflight_provider_relevant == true
            and lifecycle_calls.configuration == unchanged and credit_calls.on_configuration_changed == 1
            and library_calls.configuration == unchanged,
            "unchanged F210 preference transition was refused or skipped")

          local no_provider = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20003', new_version='5.0.21000'},
              unrelated={old_version='1.0.0'}}}
          assert(pcall(handlers.configuration, no_provider))
          assert(credit_calls.preflight == 3 and credit_calls.last_preflight_provider_relevant == false
            and lifecycle_calls.configuration == no_provider and credit_calls.on_configuration_changed == 2
            and library_calls.configuration == no_provider,
            "unrelated F210 transition acquired competing-provider refusal")
        ''')

    def test_f210_current_productivity_provider_preflights_without_a_mod_change(self):
        self.lua.execute('''
          local changed = {mod_startup_settings_changed=true,
            mod_changes={['more-infinite-research']={old_version='4.7.20003', new_version='5.0.21000'}}}
          for _, name in ipairs(TEST_COMPETING_PROVIDER_IDS) do
            install_modules(false, false, false, true)
            install_runtime(nil, {[name]='2.1.0'})
            package.loaded["runtime.competing_productivity"] = nil
            package.preload["platform.target"] = function()
              return {id="f210", recipe_productivity=true}
            end
            package.preload["runtime.competing_productivity"] = function()
              error("F210 loaded the F200 competing-productivity adapter")
            end
            CREDIT_PREFLIGHT_ERROR = "ambiguous legacy preference"
            load_control()

            local ok, message = pcall(handlers.configuration, changed)
            assert(not ok and tostring(message):find("ambiguous legacy preference", 1, true))
            assert(credit_calls.preflight == 1 and credit_calls.last_preflight_event == changed
              and credit_calls.last_preflight_provider_relevant == true,
              "current F210 provider was not recognized: " .. name)
            assert(lifecycle_calls.configuration == nil and credit_calls.on_configuration_changed == nil
              and library_calls.configuration == nil and package.loaded["runtime.competing_productivity"] == nil,
              "current F210 provider loaded the F200 adapter or allowed configuration writes: " .. name)
          end

          CREDIT_PREFLIGHT_ERROR = nil
          install_modules(false, false, false, true)
          install_runtime(nil, {unrelated='1.0.0'})
          package.preload["platform.target"] = function()
            return {id="f210", recipe_productivity=true}
          end
          load_control()
          assert(pcall(handlers.configuration, changed))
          assert(credit_calls.preflight == 1 and credit_calls.last_preflight_provider_relevant == false
            and lifecycle_calls.configuration == changed and credit_calls.on_configuration_changed == 1
            and library_calls.configuration == changed,
            "unrelated current F210 mod acquired competing-provider relevance")
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
          assert(lifecycle_calls.force_created.force == created
            and lifecycle_calls.force_reset.force == reset
            and lifecycle_calls.forces_merged.source_index == 31
            and lifecycle_calls.forces_merged.destination == destination,
            "scripted force callbacks skipped retained cap-ownership cleanup")
          assert(lifecycle_calls.research_reversed == nil and lifecycle_calls.effects_reset.force == destination,
            "unlimited effects reset skipped authored-prototype disablement")
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
          assert(#first == 54 and #second == 54)
          local seen, by_id, continuations = {}, {}, 0
          for _, row in ipairs(first) do
            assert(type(row.id) == "string" and seen[row.id] == nil)
            seen[row.id], by_id[row.id] = true, row
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
          local science = by_id["recipe-prod-research_science_pack_productivity-1"]
          assert(science and science.family == "research_science_pack_productivity"
            and science.setting == "ips-enable-research_science_pack_productivity"
            and science.cap_setting == "ips-max-level-research_science_pack_productivity"
            and #science.settings == 7)
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
          for id = 1, 3 do assert(type(handlers.events[id]) == "function") end
          for id = 4, 6 do assert(handlers.events[id] == nil) end
        ''')

    def test_repair_load_reconnects_without_save_writes_or_game_access_and_disable_clears(self):
        self.lua.execute('''
          install_modules(false, true); install_runtime(); load_control()
          local members = {[7] = {retained = true}}
          local queue = {7}
          local bucket = {queue = queue, members = members, scheduled = false, unknown = "keep"}
          storage.mir = {passive_repair = bucket, historical_other = "keep"}
          game = setmetatable({}, {__index = function() error("on_load accessed game") end})
          local saved_metatable = getmetatable(storage)
          setmetatable(storage, {__newindex = function() error("on_load wrote a saved root key") end})
          handlers.load()
          setmetatable(storage, saved_metatable)
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

    def test_repeated_load_retains_pending_repair_queue_and_has_no_ordinary_tick(self):
        # Host-only repeated Lua bootstrap/load simulation, not native save/cold-load
        # evidence. Check *nested saved values* as well as top-level identities:
        # a root __newindex guard alone cannot detect writes to existing fields.
        self.lua.execute('''
          install_modules(false, true); install_runtime(); load_control()
          local first = {retained=true, sentinel="left"}
          local second = {retained=true, sentinel="right"}
          local queue = {7, 9}
          local members = {[7]=first, [9]=second}
          local opaque = {marker="keep"}
          local bucket = {queue=queue, members=members, scheduled=false, unknown=opaque}
          local legacy = {sentinel="untouched"}
          local namespace = {passive_repair=bucket, historical_other=legacy}
          storage.mir = namespace
          local function unchanged()
            assert(storage.mir == namespace and namespace.passive_repair == bucket)
            assert(bucket.queue == queue and #queue == 2 and queue[1] == 7 and queue[2] == 9)
            assert(bucket.members == members and members[7] == first and members[9] == second)
            assert(first.retained and first.sentinel == "left" and second.retained and second.sentinel == "right")
            assert(bucket.scheduled == false and bucket.unknown == opaque and opaque.marker == "keep")
            assert(namespace.historical_other == legacy and legacy.sentinel == "untouched")
          end
          for cold = 1, 2 do
            -- A new control module rebinds subscriptions; the same saved
            -- namespace must remain intact even with an inaccessible world.
            remote.interfaces = {}
            load_control()
            unchanged()
            local ordinary_game = game
            game = setmetatable({}, {
              __index = function() error("on_load read game") end,
              __newindex = function() error("on_load wrote game") end
            })
            handlers.load()
            unchanged()
            assert(type(handlers.nth[60]) == "function")
            assert(handlers.events[defines.events.on_tick] == nil)
            local scheduled = handlers.nth[60]
            local calls = handlers.nth_calls
            handlers.load()
            unchanged()
            assert(handlers.nth[60] == scheduled and handlers.nth_calls == calls)
            assert(handlers.events[defines.events.on_tick] == nil)
            game = ordinary_game
          end
        ''')

    def test_data_stage_keeps_the_published_shortcut_and_private_native_admission(self):
        self.lua.execute('''
          local function capture(space_age)
            emitted = nil
            mods = space_age and {["space-age"] = "2.0.0"} or {}
            data = {extend = function(_, rows) emitted = rows end}
            assert(loadfile(data_source))()
            assert(#emitted == 2)
            do
              local private=emitted[2]
              assert(private.type=="mod-data" and private.name=="more-infinite-research-native-adoptions")
              assert(private.data.schema==1 and next(private.data.owners)==nil and next(private.data.credits)==nil)
            end
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
        source = (ROOT / "source/runtime/bootstrap.lua").read_text(encoding="utf-8")
        control = (ROOT / "source/control.lua").read_text(encoding="utf-8")
        self.assertIn("worker_completion_tick and on_worker_completion_tick or nil", source)
        self.assertNotIn("script.on_event(events.on_tick, on_worker_completion_tick)", source)
        self.assertNotIn("require(", source[source.index("function M.register"):])
        self.assertIn('require("runtime.bootstrap")', control)
        self.assertIn("remote.add_interface", control)

    def test_worker_completion_tick_is_bound_only_for_a_durable_marker(self):
        self.lua.execute(r'''
          install_modules(false);install_runtime();load_control()
          local worker=require("runtime.worker_robot_storage")
          local due,calls=101,{}
          worker.default_owner_completion_pending_tick=function()return due end
          worker.default_owner_on_completion_tick=function(event)
            calls[#calls+1]=event.tick;due=nil;return true
          end
          handlers.init()
          assert(type(handlers.events[defines.events.on_tick])=="function")
          handlers.events[defines.events.on_tick]({tick=101})
          assert(#calls==1 and calls[1]==101)
          assert(handlers.events[defines.events.on_tick]==nil,
            "completion observation remained scheduled after its marker cleared")
        ''')

    def test_worker_queue_tick_is_restored_from_the_saved_marker_and_then_unbound(self):
        self.lua.execute(r'''
          install_modules(false);install_runtime();load_control()
          local worker=require("runtime.worker_robot_storage")
          local waiting,calls=true,0
          worker.prepared_queue_pending=function()return waiting end
          worker.on_prepared_queue_tick=function(event)
            assert(event.tick==102);calls=calls+1;waiting=false
          end
          handlers.load()
          assert(type(handlers.events[defines.events.on_tick])=="function")
          handlers.events[defines.events.on_tick]({tick=102})
          assert(calls==1 and handlers.events[defines.events.on_tick]==nil)
        ''')

    def test_worker_completion_marker_does_not_publish_until_the_later_settlement(self):
        self.lua.execute(r'''
          install_modules(true);install_runtime();load_control()
          local worker=require("runtime.worker_robot_storage")
          local lifecycle=require("runtime.lifecycle")
          local due,calls,restored=nil,{},nil
          lifecycle.on_research_finished=function(event)calls[#calls+1]=event end
          lifecycle.record_completed_worker_cap=function(force, enabled)
            assert(force==player.force);restored=enabled
          end
          worker.default_owner_completion_pending_tick=function()return due end
          worker.default_owner_on_research_finished=function(event)
            due=401;return true,false
          end
          worker.default_owner_on_completion_tick=function(event, record_completed_worker_cap)
            assert(event.tick==401)
            record_completed_worker_cap(player.force, false)
            due=nil;return true,{player.force}
          end
          player.force.technologies["worker-robots-storage-4"]={name="worker-robots-storage-4"}
          handlers.init()
          require("runtime.library").native_subscription_needs=function()
            error("worker completion scanned saved Library views while closed")
          end
          local event={research={valid=true,name="mir-worker-storage-published517-4",force=player.force}}
          handlers.events[defines.events.on_research_finished](event)
          assert(#calls==1 and calls[1]==event,
            "deferred completion published the canonical public research early")
          assert(restored==nil,"deferred completion recorded cap restoration early")
          assert(type(handlers.events[defines.events.on_tick])=="function")
          handlers.events[defines.events.on_tick]({tick=401})
          assert(#calls==2 and calls[2].research==player.force.technologies["worker-robots-storage-4"])
          assert(restored==false,"deferred completion lost the holder's foreign disablement")
          assert(handlers.events[defines.events.on_tick]==nil)
        ''')

    def test_required_catalogue_worker_exports_refuse_before_bootstrap_registration(self):
        self.lua.execute(r'''
          local actual_catalogue = require("runtime.catalogue")
          local names = {
            "worker_storage_route", "worker_default_split", "finite_research_speed_provider"
          }
          for _, target_id in ipairs({"f200", "f210"}) do
            for _, name in ipairs(names) do
              for _, kind in ipairs({"missing", "nonfunction"}) do
              install_modules(false); install_runtime()
              local supplied = {}
              for key, value in pairs(actual_catalogue) do supplied[key] = value end
              if kind == "nonfunction" then
                supplied[name] = false
                assert(rawget(supplied, name) == false and type(rawget(supplied, name)) == "boolean",
                  "nonfunction catalogue opponent was not false: " .. name)
              else
                supplied[name] = nil
                assert(rawget(supplied, name) == nil,
                  "missing catalogue opponent unexpectedly retained a value: " .. name)
              end
              package.loaded["runtime.catalogue"] = nil
              package.loaded["runtime.worker_robot_storage"] = nil
              package.loaded["runtime.finite_research_speed"] = nil
              package.preload["platform.target"] = function()
                local target = dofile(player_root .. "/platform/target.lua")
                target.id = target_id
                return target
              end
              package.preload["runtime.catalogue"] = function() return supplied end
              local ok, message = pcall(load_control)
              assert(not ok and tostring(message):find("MIR runtime catalogue requires callable " .. name, 1, true),
                target_id .. " " .. kind .. " required catalogue export was treated as an absent result: " .. name)
              assert(next(remote.interfaces) == nil and next(commands.registered) == nil
                and handlers.init == nil and handlers.configuration == nil and handlers.load == nil
                and next(handlers.events) == nil and next(handlers.nth) == nil,
                target_id .. " " .. kind .. " export registered a callback or command before refusal: " .. name)
              assert(next(lifecycle_calls) == nil and next(library_calls) == nil
                and package.loaded["runtime.worker_robot_storage"] == nil
                and package.loaded["runtime.finite_research_speed"] == nil,
                target_id .. " " .. kind .. " export reached worker, finite-speed, lifecycle or Library application: " .. name)
              end
            end
          end
        ''')

    def test_historical_target_does_not_require_current_catalogue_worker_exports(self):
        self.lua.execute(r'''
          install_modules(false); install_runtime()
          local actual_catalogue = require("runtime.catalogue")
          local supplied = {}
          for key, value in pairs(actual_catalogue) do supplied[key] = value end
          supplied.worker_storage_route = nil
          supplied.worker_default_split = false
          supplied.finite_research_speed_provider = nil
          package.loaded["runtime.catalogue"] = nil
          package.preload["platform.target"] = function()
            local target = dofile(player_root .. "/platform/target.lua")
            target.id = "f018"
            return target
          end
          package.preload["runtime.catalogue"] = function() return supplied end
          local ok, message = pcall(load_control)
          assert(ok, message)
          assert(next(remote.interfaces) ~= nil and handlers.init ~= nil and handlers.configuration ~= nil,
            "historical target lost the ordinary bootstrap route")
        ''')

    def test_callable_catalogue_worker_exports_keep_absent_results(self):
        self.lua.execute(r'''
          install_modules(false); install_runtime()
          local catalogue = require("runtime.catalogue")
          catalogue.worker_storage_route = function() return nil end
          catalogue.worker_default_split = function() return false end
          catalogue.finite_research_speed_provider = function() return nil end
          local ok, message = pcall(load_control)
          assert(ok, message)
          ok, message = pcall(handlers.init)
          assert(ok, message)
          ok, message = pcall(handlers.configuration, {mod_changes = {}})
          assert(ok, message)
          assert(lifecycle_calls.init == 1 and lifecycle_calls.configuration ~= nil
            and library_calls.init == 1 and library_calls.configuration ~= nil,
            "callable absent worker results lost the ordinary lifecycle route")
        ''')

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
          assert(lifecycle_calls.force_created.force == two
            and lifecycle_calls.force_reset.force == two
            and lifecycle_calls.forces_merged.source_index == 1
            and lifecycle_calls.forces_merged.destination == two)
        ''')


    def test_diagnostic_headers_run_only_on_init_and_configuration(self):
        self.lua.execute('''
          install_modules(false); install_runtime()
          headers, diagnostic_exports = {}, 0
          helpers={write_file=function() end}
          package.preload["runtime.diagnostics"]=function()
            return {startup=function(stage) headers[#headers+1]=stage end,
              export=function(index) diagnostic_exports=diagnostic_exports+1;diagnostic_player=index end}
          end
          load_control()
          assert(#headers==0)
          handlers.init();handlers.configuration({mod_changes={}})
          assert(#headers==2 and headers[1]=="MIR initialization" and headers[2]=="MIR configuration change")
          handlers.load()
          library_pending=true
          handlers.events[8]({player_index=1, element={name="mir_library_query"}})
          local maintenance=handlers.nth[61]
          assert(type(maintenance)=="function")
          maintenance({tick=61})
          assert(#headers==2)
          commands.registered["mir-diagnostics-export"].callback({player_index=1})
          assert(diagnostic_exports==1 and diagnostic_player==1)
          commands.registered["mir-diagnostics-export"].callback({})
          assert(diagnostic_exports==2 and diagnostic_player==nil)
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
