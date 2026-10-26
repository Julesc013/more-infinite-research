"""Pure Lua 5.2 controls for the private MIR5 Library slice, not native evidence."""
import argparse
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          package.preload["research.catalogue"] = function()
            return {
              declared = function()
                return {
                  {id = "recipe-prod-research_gears-1", name = "Iron gear wheel productivity",
                    family = "mir", cap = 2, cap_setting = "ips-max-level-research_gears",
                    finite = false, max_level = "infinite"}
                }
              end
            }
          end

          package.preload["presentation.library_model"] = function()
            local function copy(row, technology, queued_count, queue_index, current, display_name)
              local result = {
                id = row.id, name = display_name or row.name, family = row.family, finite = row.finite,
                max_level = row.max_level, cap = row.cap, cap_setting = row.cap_setting,
                cap_state = row.cap and "finite" or "unlimited",
                current_level = technology and technology.level or 1,
                researched = technology and technology.researched or false,
                enabled = technology and technology.enabled or false,
                visible = technology and technology.visible_when_disabled or false,
                queued_count = queued_count, queue_index = queue_index, current = current,
                prerequisites = {}
              }
              if current or queued_count > 0 then result.status = "queued"
              elseif result.enabled then result.status = "ready"
              else result.status = "locked" end
              return result
            end
            local function queue_facts(force, id)
              local count, first = 0, nil
              for index, queued in ipairs(force.research_queue or {}) do
                local name = type(queued) == "table" and queued.name or queued
                if name == id then
                  count = count + 1
                  if first == nil then first = index end
                end
              end
              local current = force.current_research
              local current_name = type(current) == "table" and current.name or current
              return count, first, current_name == id
            end
            return {
              normalize = function(view)
                local mode = type(view.mode) == "number" and view.mode or 1
                if mode < 1 or mode > 3 or mode ~= math.floor(mode) then mode = 1 end
                local status = type(view.status) == "number" and view.status or 1
                if status < 1 or status > 4 or status ~= math.floor(status) then status = 1 end
                local page = type(view.page) == "number" and view.page or 1
                if page < 1 or page > 30000 or page ~= math.floor(page) then page = 1 end
                local sort = view.sort
                if sort ~= "progression" and sort ~= "native" and sort ~= "name-asc" and sort ~= "name-desc" then
                  sort = "progression"
                end
                local stable_sort = view.stable_sort
                if stable_sort ~= "progression" and stable_sort ~= "native" then stable_sort = "progression" end
                local visibility = type(view.visibility) == "number" and view.visibility or 1
                if visibility < 1 or visibility > 3 or visibility ~= math.floor(visibility) then visibility = 1 end
                local hidden = {}
                if type(view.hidden) == "table" then
                  for id, hidden_value in pairs(view.hidden) do
                    if hidden_value == true and type(id) == "string" then hidden[id] = true end
                  end
                end
                return {
                  query = type(view.search) == "string" and view.search or (type(view.query) == "string" and view.query or ""),
                  family = view.family == "mir" and "mir" or "all",
                  mode = mode,
                  status = status,
                  page = page,
                  sort = sort,
                  stable_sort = stable_sort,
                  visibility = visibility,
                  hidden = hidden,
                  selected = type(view.selected) == "string" and view.selected or nil
                }
              end,
              rows = function(force, rows, view, translations)
                assert(type(translations) == "table")
                local output = {}
                for _, row in ipairs(rows) do
                  local technology = force.technologies[row.id]
                  local display_name = translations[row.id] or row.name
                  local name = string.lower(display_name)
                  local query = string.lower(view.query or view.search or "")
                  local queued_count, queue_index, current = queue_facts(force, row.id)
                  local copied = copy(row, technology, queued_count, queue_index, current, display_name)
                  if (view.family == "all" or row.family == view.family)
                    and (query == "" or string.find(name, query, 1, true))
                    and (view.status == 1
                      or (view.status == 2 and copied.status == "ready")
                      or (view.status == 3 and copied.status == "locked")
                      or (view.status == 4 and copied.status == "queued")) then
                    output[#output + 1] = copied
                  end
                end
                return output
              end,
              detail = function(force, rows, view, translations)
                for _, row in ipairs(rows) do
                  if row.id == view.selected then
                    return {cost = {count = 8000, time = 60}, prerequisites = {},
                      effects = {{type = "change-recipe-productivity", change = 0.1}}}
                  end
                end
                return nil
              end
            }
          end

          function gui_style()
            local values = {}
            local function assert_int32(key, value)
              assert(type(value) == "number" and value == math.floor(value)
                and value >= -2147483648 and value <= 2147483647,
                "LuaStyle." .. key .. " requires an int32")
            end
            return setmetatable({}, {
              __index = function(_, key) return values[key] end,
              __newindex = function(_, key, value)
                if key == "width" then
                  assert_int32(key, value)
                  -- LuaStyle.width writes both bounds. Keep this host double
                  -- aligned with the native F200/F210 GUI contract.
                  values.minimal_width, values.maximal_width = value, value
                elseif key == "height" then
                  assert_int32(key, value)
                  values.minimal_height, values.maximal_height = value, value
                elseif key == "minimal_width" or key == "maximal_width"
                    or key == "minimal_height" or key == "maximal_height" then
                  assert_int32(key, value)
                  values[key] = value
                else
                  values[key] = value
                end
              end
            })
          end

          function gui_container(parent)
            local value = {valid = true, parent = parent, _parent = parent, _children = {}, style = gui_style()}
            value.auto_center = true
            value.force_auto_center = function()
              assert(value.auto_center == true, "native force_auto_center requires an auto-centering frame")
              value.force_auto_center_calls = (value.force_auto_center_calls or 0) + 1
            end
            value.add = function(spec)
              if spec.type == "tabbed-pane" and spec.name == "mir_library_tabs" then
                assert(spec.selected_tab_index == nil, "MIR must select a tab only after add_tab entries exist")
              end
              local element = gui_container(value)
              for key, field in pairs(spec) do element[key] = field end
              value._children[#value._children + 1] = element
              if element.name then value[element.name] = element end
              element.destroy = function()
                if not element.valid then return end
                element.valid = false
                if element.name then element._parent[element.name] = nil end
              end
              element.clear = function()
                for _, child in ipairs(element._children) do
                  child.valid = false
                  if child.name then element[child.name] = nil end
                end
                element._children = {}
              end
              element.scroll_to_item = function(index, mode)
                element.scrolled_to = {index = index, mode = mode}
              end
              element.add_tab = function(tab, content)
                element._tabs = element._tabs or {}
                element._tabs[#element._tabs + 1] = {tab = tab, content = content}
              end
              return element
            end
            return value
          end

          function research_content(root)
            local tabs = root and root["mir_library_tabs"]
            return tabs and tabs["mir_library_research_content"] or (root and root["mir_library_content"])
          end

          function boot()
            storage = {}
            settings = {startup = {}}
            screen = gui_container(nil)
            gear = {valid = true, name = "recipe-prod-research_gears-1", level = 3,
              researched = true, enabled = false, visible_when_disabled = true,
              localised_name = "Iron gear wheel productivity",
              prototype = {max_level = 4294967295}}
            foreign = {valid = true, name = "foreign-research", level = 1,
              researched = false, enabled = true, visible_when_disabled = false,
              localised_name = "Foreign research", prototype = {max_level = 3}}
            player = {valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
              force = {
                index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
                research_queue = {gear}, current_research = gear, research_progress = .5,
                add_research = function() error("Library must not add native research") end,
                cancel_current_research = function() error("Library must not cancel native research") end
              }}
            player.set_shortcut_toggled = function(name, value)
              player.shortcut_name, player.shortcut_toggled = name, value
            end
            player.open_technology_gui = function(technology)
              player.opened_technology = technology
            end
            player.translation_requests, player.next_translation_id = {}, 0
            player.request_translation = function(localised)
              player.next_translation_id = player.next_translation_id + 1
              local request = {id = player.next_translation_id, localised = localised}
              player.translation_requests[#player.translation_requests + 1] = request
              return request.id
            end
            game = {tick = 0, get_player = function(index) return index == 1 and player or nil end}
            package.loaded["runtime.library"] = nil
            library = require("runtime.library")
          end

          function route_native_events(reload_library, caps_active)
            native_handlers, native_ticks = {events={}}, {}
            native_cap_completions = 0
            caps_active = caps_active == true
            package.loaded["runtime.lifecycle"] = nil
            package.preload["runtime.lifecycle"] = function()
              return {caps_active=function() return caps_active end,cap_limits=function() return {} end,
                on_init=function() end,on_configuration_changed=function() end,on_load=function() end,
                on_research_finished=function() native_cap_completions=native_cap_completions+1 end,
                on_force_created=function() end,on_force_reset=function() end,on_forces_merged=function() end}
            end
            script = {active_mods={base="2.1.23"},
              on_event=function(id,callback) native_handlers.events[id]=callback end,
              on_nth_tick=function(interval,callback) native_ticks[interval]=callback end,
              on_init=function(callback) native_handlers.init=callback end,
              on_load=function(callback) native_handlers.load=callback end,
              on_configuration_changed=function(callback) native_handlers.configuration=callback end}
            defines = {events={on_research_finished=1,on_gui_closed=2,on_research_started=3,
              on_research_cancelled=4,on_research_reversed=5,on_research_queued=6,on_research_moved=7,
              on_technology_effects_reset=8,on_force_reset=9,on_forces_merged=10,
              on_player_left_game=11,on_player_joined_game=12,on_player_changed_force=13}}
            remote = {interfaces={},add_interface=function(name,methods) remote.interfaces[name]=methods end}
            commands = {add_command=function() end}
            if reload_library then
              package.loaded["runtime.library"] = nil
              library = require("runtime.library")
            end
            package.loaded["runtime.bootstrap"] = nil
            require("runtime.bootstrap").register()
          end

          function boot_native_events()
            boot()
            gear.force, foreign.force = player.force, player.force
            route_native_events(false)
          end

          function open_routed(options)
            assert(remote.interfaces["more-infinite-research-browser"].open(1,options) == true)
            return player.gui.screen["mir_research_browser"]
          end

          function queued_rows()
            return #research_content(player.gui.screen["mir_research_browser"])["mir_library_results"].items
          end
        ''')

    def test_native_research_events_refresh_once_after_engine_state_settles_and_unsubscribe_on_close(self):
        self.lua.execute(r'''
          boot_native_events()
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil)
          local root = open_routed({status=4,selected=gear.name})
          assert(queued_rows() == 1)
          assert(type(native_handlers.events[1]) == "function", "open Library did not subscribe to native research")
          local query = root["mir_library_filters"]["mir_library_query"]
          -- The callback can precede the final native queue transition.
          native_handlers.events[1]({research=gear})
          native_handlers.events[3]({research=gear})
          native_handlers.events[7]({force=player.force})
          assert(queued_rows() == 1 and type(native_ticks[1]) == "function")
          gear.level = 4
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local queue = player.force.research_queue
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
          assert(player.gui.screen["mir_research_browser"] == root
            and root["mir_library_filters"]["mir_library_query"] == query and query.valid)
          assert(player.force.research_queue == queue and player.force.current_research == nil
            and player.force.research_progress == 0 and gear.level == 4)
          native_handlers.events[2]({player_index=1,element=root})
          for _, id in ipairs({1,3,4,5,6,7}) do assert(native_handlers.events[id] == nil) end
          assert(native_ticks[1] == nil and not library.native_subscription_needs())
        ''')

    def test_pending_native_view_refresh_reconstructs_after_cold_load_without_game_or_save_writes(self):
        self.lua.execute(r'''
          boot_native_events()
          open_routed({status=4})
          native_handlers.events[6]({research=gear})
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local saved, view, available_game = storage, storage.mir_library.players[1], game
          assert(view.open and view.refresh_pending)
          game = nil
          route_native_events(true)
          native_handlers.load()
          assert(storage == saved and storage.mir_library.players[1] == view and view.open and view.refresh_pending)
          assert(type(native_handlers.events[1]) == "function" and type(native_ticks[1]) == "function")
          game = available_game
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
        ''')

    def test_native_events_refresh_the_actual_library_model_and_selected_detail(self):
        self.lua.execute(r'''
          -- Exercise the production query model as well as the actual GUI and
          -- bootstrap; the other controls isolate their GUI boundary with a
          -- small model double.
          package.preload["presentation.library_model"] = nil
          package.loaded["presentation.library_model"] = nil
          boot_native_events()
          local root = open_routed({status=4,selected=gear.name})
          assert(queued_rows() == 1)
          native_handlers.events[1]({research=gear})
          gear.level, gear.researched, gear.enabled = 4,false,true
          player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
          local queue = player.force.research_queue
          native_ticks[1]({tick=1})
          assert(queued_rows() == 0 and native_ticks[1] == nil)
          assert(open_routed({status=1,selected=gear.name}) == root)
          local detail = research_content(root)["mir_library_detail"]
          assert(detail["mir_library_detail_level"].caption[2] == 4)
          native_handlers.events[5]({research=gear})
          gear.level = 3
          native_ticks[1]({tick=2})
          assert(research_content(root)["mir_library_detail"]["mir_library_detail_level"].caption[2] == 3)
          assert(player.force.research_queue == queue and player.force.current_research == nil
            and player.force.research_progress == 0 and gear.level == 3 and not gear.researched)
        ''')

    def test_closing_a_view_retains_independent_cap_research_callbacks(self):
        self.lua.execute(r'''
          boot_native_events()
          route_native_events(false,true)
          local root = open_routed()
          native_handlers.events[2]({player_index=1,element=root})
          assert(type(native_handlers.events[1]) == "function" and type(native_handlers.events[3]) == "function")
          assert(native_handlers.events[6] == nil and native_handlers.events[7] == nil and native_ticks[1] == nil)
          native_handlers.events[1]({research=gear})
          assert(native_cap_completions == 1 and native_ticks[1] == nil)
        ''')

    def test_queue_reversal_effect_reset_and_force_boundaries_route_live_native_views(self):
        self.lua.execute(r'''
          for _, id in ipairs({4,5,6,7,8,9,10}) do
            boot_native_events()
            open_routed({status=4})
            player.force.research_queue, player.force.current_research, player.force.research_progress = {},nil,0
            native_handlers.events[id]({research=gear,force=player.force,destination=player.force,source_index=2})
            assert(type(native_ticks[1]) == "function", "native boundary did not schedule view refresh: "..id)
            native_ticks[1]({tick=1})
            assert(queued_rows() == 0 and native_ticks[1] == nil)
          end
        ''')

    def test_force_change_refreshes_an_open_queue_tab_without_a_translation_cache(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed({tab="queue"})
          local content = root["mir_library_tabs"]["mir_library_queue_content"]
          assert(#content["mir_library_queue_list"].items == 1 and #player.translation_requests == 0)
          player.force = {index=2,technologies={[gear.name]=gear},research_queue={},research_progress=0}
          native_handlers.events[13]({player_index=1})
          assert(player.gui.screen["mir_research_browser"] == root)
          assert(#content["mir_library_queue_list"].items == 0,
            "force change kept the old queue when no translation cache existed")
        ''')

    def test_native_refresh_ignores_other_forces_and_foreign_frames_and_rejoins_live_views(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed({status=4})
          native_handlers.events[7]({force={index=2}})
          assert(native_ticks[1] == nil)
          player.connected = false
          native_handlers.events[11]({player_index=1})
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil and root.valid)
          player.connected = true
          native_handlers.events[12]({player_index=1})
          assert(storage.mir_library.players[1].open == true
            and type(native_handlers.events[1]) == "function")
          root.destroy()
          local foreign_root = screen.add{type="frame",name="mir_research_browser"}
          native_handlers.events[5]({research=gear})
          assert(foreign_root.valid and screen["mir_research_browser"] == foreign_root)
          assert(native_ticks[1] == nil and native_handlers.events[1] == nil)
          assert(storage.mir_library.translations.working == nil,
            "lost owned frame retained its working cache")
        ''')

    def test_join_without_an_owned_root_retires_open_view_subscriptions_but_keeps_issued_translation_ids(self):
        self.lua.execute(r'''
          boot_native_events()
          local root = open_routed()
          native_handlers.events[1]({research=gear})
          local state, view = storage, storage.mir_library.players[1]
          local ledger = state.mir_library.translations
          local issued = ledger.active[1].pending[1].request_id
          local requests, available_game = #player.translation_requests, game
          assert(view.open and view.refresh_pending and library.subscription_needs())

          -- Loading reconnects only local references. It must not consume the
          -- issued native ID or touch a game/GUI object.
          game = nil
          route_native_events(true)
          native_handlers.load()
          assert(storage == state and storage.mir_library.players[1] == view
            and ledger.active[1].pending[1].request_id == issued
            and view.open and view.refresh_pending)
          game = available_game

          root.destroy()
          native_handlers.events[12]({player_index=1})
          local open, pending = library.native_subscription_needs()
          assert(not open and not pending and not view.open and not view.refresh_pending)
          assert(native_handlers.events[1] == nil and native_ticks[1] == nil)
          assert(#player.translation_requests == requests and player.gui.screen["mir_research_browser"] == nil)
          assert(ledger.active[1] ~= nil and ledger.active[1].pending[1].request_id == issued
            and library.subscription_needs(), "issued IDs remain for bounded expiry cleanup")
          assert(type(native_ticks[61]) == "function")
        ''')

    def test_pending_view_refresh_retires_translation_work_after_the_owned_root_disappears(self):
        self.lua.execute(r'''
          boot_native_events()
          local root=open_routed()
          native_handlers.events[1]({research=gear})
          root.destroy()
          native_ticks[1]({tick=1})
          assert(storage.mir_library.translations.working==nil and native_ticks[1]==nil)
          assert(player.gui.screen["mir_research_browser"]==nil and #player.translation_requests==1)
          assert(library.subscription_needs(),"issued ID was discarded with the working cache")
        ''')

    def test_native_refresh_orders_pending_players_independently_of_saved_map_iteration(self):
        self.lua.execute(r'''
          boot_native_events()
          local order = {}
          player.set_shortcut_toggled = function(_, active) if active then order[#order+1]=1 end end
          local second = {valid=true,index=2,locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},request_translation=function() return nil end,
            set_shortcut_toggled=function(_, active) if active then order[#order+1]=2 end end}
          game.get_player = function(index) return index == 1 and player or index == 2 and second or nil end
          open_routed({status=4})
          assert(remote.interfaces["more-infinite-research-browser"].open(2,{status=4}))
          local views = storage.mir_library.players
          setmetatable(views, {__pairs=function()
            local index=3
            return function() index=index-1; if index>0 then return index,views[index] end end
          end})
          native_handlers.events[1]({research=gear})
          order = {}
          native_ticks[1]({tick=1})
          assert(table.concat(order,",") == "1,2", "pending view order follows hash/insertion traversal")
          assert(native_ticks[1] == nil and storage.mir_library.players[1].query == ""
            and storage.mir_library.players[2].query == "")
        ''')

    def test_authored_catalogue_builds_lazily_once_until_configuration_changes(self):
        self.lua.execute(r'''
          local catalogue = require("research.catalogue")
          local original, builds, family = catalogue.declared, 0, "mir"
          catalogue.declared = function()
            builds = builds + 1
            local rows = original()
            rows[1].family = family
            return rows
          end
          boot()
          library.on_init(); library.on_load()
          assert(builds == 0, "closed Library constructed authored catalogue during parse/init/load")
          local queue, current, progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          local root = library.open(player, {selected=gear.name})
          assert(builds == 1, "one Library open rebuilt authored catalogue "..builds.." times")
          local model = require("presentation.library_model")
          local original_rows, observed_level = model.rows, nil
          model.rows = function(force, ...)
            observed_level = force.technologies[gear.name].level
            return original_rows(force, ...)
          end
          gear.level = 4
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "gear"
          library.on_gui_text_changed({player_index=1,element=query})
          library.close(player)
          library.open(player)
          assert(builds == 1, "refresh/reopen rebuilt unchanged authored metadata")
          assert(observed_level == 4, "metadata cache retained stale native research facts")

          library.close(player)
          family = "research_updated"
          library.on_configuration_changed()
          assert(builds == 1, "configuration rebuilt metadata for a closed Library")
          library.open(player, {family=family})
          assert(builds == 2 and storage.mir_library.players[1].family == family,
            "configuration retained stale authored metadata")
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress,
            "metadata reuse changed native research state")
        ''')

    def test_requested_view_fits_scaled_display_wraps_details_and_converts_native_ticks(self):
        self.lua.execute(r'''
          boot()
          player.display_resolution, player.display_scale = {width=1280,height=720}, 1.25
          local model = require("presentation.library_model")
          local long_ingredient = "very-long-native-science-ingredient-identifier-for-detail-width"
          model.detail = function()
            return {cost={count=8000,energy=3600,ingredients={{name=long_ingredient,amount=1}}},prerequisites={},
              effects={{type="change-recipe-productivity",change=.10000000149}}}
          end
          local root = library.open(player,{selected=gear.name,query="gear"})
          local root_width = root.style.maximal_width
          assert(root.style.minimal_width == root_width and root_width <= 1280/1.25
            and root.style.maximal_height <= 720/1.25)
          assert(root.auto_center == true and root.force_auto_center_calls == 1)
          local filters = root["mir_library_filters"]
          assert(filters.type == "table" and filters.column_count == 4)
          local family_style = filters["mir_library_family"].style
          assert(family_style.minimal_width == family_style.maximal_width and family_style.maximal_width <= 280)
          local content = research_content(root)
          assert(content.type == "scroll-pane" and content.horizontal_scroll_policy == "never")
          assert(content.style.maximal_height < root.style.maximal_height and content.style.maximal_width < root_width)
          local detail = content["mir_library_detail"]
          assert(detail.style.minimal_width == content.style.maximal_width
            and detail.style.maximal_width == content.style.maximal_width)
          local cost = content["mir_library_detail"]["mir_library_detail_cost"]
          assert(cost.caption[1] == "mir-browser.research-cost" and tonumber(cost.caption[3]) == 60)
          assert(cost.style.single_line == false and cost.style.maximal_width == detail.style.maximal_width)
          local science = detail["mir_library_science_1"]
          assert(science.caption[2] == long_ingredient and science.style.maximal_width == detail.style.maximal_width)
          assert(content["mir_library_detail"]["mir_library_effect_1"].caption[2] == "10")
          assert(filters["mir_library_family_label"].caption[1] == "mir-browser.filter-scope")
          library.close(player)
          storage.mir_library.players[1].location = {x=17,y=29}
          player.display_resolution, player.display_scale = {width=1280,height=720}, 2
          root = library.open(player,{selected=gear.name})
          assert(root["mir_library_filters"].column_count == 2)
          assert(root.style.minimal_width == root.style.maximal_width and root.style.maximal_width <= 640
            and root.style.maximal_height <= 360)
          assert(root.location.x == 17 and root.location.y == 29 and root.force_auto_center_calls == nil,
            "a saved drag location must win over native force_auto_center")
          ''')

    def test_fractional_display_scale_writes_only_int32_gui_dimensions(self):
        self.lua.execute(r'''
          boot()
          -- 1042 / 1.25 - 32 is 801.6, and the two-column control calculation
          -- is fractional again. The native LuaStyle setters take int32 only.
          player.display_resolution, player.display_scale = {width=1042,height=768}, 1.25
          local root = library.open(player,{selected=gear.name})
          assert(root.style.minimal_width == 801 and root.style.maximal_width == 801)
          assert(root.style.minimal_height == 582 and root.style.maximal_height == 582)
          assert(root.force_auto_center_calls == 1)
          local filters = root["mir_library_filters"]
          local family = filters["mir_library_family"]
          assert(family.style.minimal_width == 225 and family.style.maximal_width == 225)
          local tabs = root["mir_library_tabs"]
          assert(tabs.style.maximal_width == 769)
          local content = research_content(root)
          assert(content.style.minimal_width == 753 and content.style.maximal_width == 753)
          assert(content.style.minimal_height == 352 and content.style.maximal_height == 352)
        ''')

    def test_pure_prototype_constructor_preserves_published_shortcut_identity(self):
        self.lua.globals().prototype_source = (ROOT / "source/presentation/shortcut.lua").as_posix()
        self.lua.execute('''
          local presentation = assert(loadfile(prototype_source))()
          local base = presentation.research_library_shortcut(false)
          assert(base.type == "shortcut" and base.name == "mir-research-browser")
          assert(base.action == "lua" and base.toggleable and base.order == "z[more-infinite-research]-a[research-browser]")
          assert(base.icon == "__base__/graphics/icons/lab.png" and base.icon_size == 64)
          local space_age = presentation.research_library_shortcut(true)
          assert(space_age.icon == "__space-age__/graphics/technology/research-productivity.png" and space_age.icon_size == 256)
          assert(base ~= space_age and base.small_icon == base.icon and space_age.small_icon == space_age.icon)
        ''')

    def test_all_shipped_locales_cover_the_recovered_library_tab_surface(self):
        required = {
            "availability", "availability-empty", "configuration-source", "count", "effective-values",
            "help", "help-summary", "productivity-increment", "queue-empty", "queue-tab",
            "not-added",
            "science-ingredient", "scope-startup", "setting-off", "setting-on", "setting-provenance",
            "settings", "settings-count", "settings-empty", "settings-scope-options",
            "settings-scope-research", "source-direct", "source-mirset1",
        }
        locales = sorted((ROOT / "source/locale").glob("*/mir-library.cfg"))
        self.assertEqual(len(locales), 50)
        for path in locales:
            keys = {line.split("=", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue(required <= keys, path)

    def test_en_and_de_localize_the_authored_availability_reasons(self):
        required = {
            "availability-entry", "availability-requires-space-age", "availability-native-research-productivity",
            "availability-not-available-in-bob-angel-profile", "availability-not-available-in-bobtech-angel-profile",
        }
        for language in ("en", "de"):
            path = ROOT / "source/locale" / language / "mir-library.cfg"
            keys = {line.split("=", 1)[0] for line in path.read_text(encoding="utf-8").splitlines()
                    if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue(required <= keys, path)
            names = ROOT / "source/locale" / language / "more-infinite-research.cfg"
            name_keys = {line.split("=", 1)[0] for line in names.read_text(encoding="utf-8").splitlines()
                         if line and not line.startswith((";", "#", "[")) and "=" in line}
            self.assertTrue({
                "more-infinite-research.research_agricultural_growth_speed",
                "more-infinite-research.research_spoilage_preservation",
                "more-infinite-research.research_lab_productivity",
            } <= name_keys, names)

    def test_availability_mode_searches_authored_rows_without_native_actions(self):
        self.lua.execute(r'''
          script = {active_mods = {}}
          boot()
          local native_queue, native_current, native_progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress

          local root = library.open(player, {tab = "availability"})
          local content = research_content(root)
          assert(content["mir_library_availability_1"] ~= nil and content["mir_library_availability_2"] ~= nil
            and content["mir_library_availability_empty"] == nil)
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "spoilage-preservation"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(content["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_spoilage_preservation"
            and content["mir_library_availability_2"] == nil)

          script.active_mods = {["space-age"] = "2.1.23"}
          query.text = ""
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(content["mir_library_availability_empty"] ~= nil,
            "Space Age must not show the two requires-Space-Age rows")

          local owner = {valid = true, prototype = {effects = {
            {type = "laboratory-productivity", modifier = .1}
          }}}
          player.force.technologies["research-productivity"] = owner
          library.open(player, {tab = "availability", query = "lab"})
          assert(content["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_lab_productivity"
            and content["mir_library_availability_1"].caption[3][1]
              == "mir-browser.availability-native-research-productivity")

          owner.prototype.effects[1].modifier = .1001
          library.open(player, {tab = "availability", query = ""})
          assert(content["mir_library_availability_empty"] ~= nil
            and content["mir_library_availability_1"] == nil,
            "a malformed named native owner must not produce an explanation")
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == native_progress and gear.level == 3 and gear.enabled == false)
        ''')

    def test_availability_uses_parse_time_effective_streams_without_profile_resolution_on_refresh(self):
        self.lua.execute(r'''
          local loads, rows_calls = 0, 0
          local streams = {research_material_lead = {enabled = false}}
          package.preload["runtime.configuration"] = function()
            loads = loads + 1
            return {streams = streams}
          end
          package.preload["presentation.availability"] = function()
            return {
              rows = function(active_mods, selected_target, force, query, supplied_streams)
                rows_calls = rows_calls + 1
                assert(supplied_streams == streams and supplied_streams.research_material_lead.enabled == false)
                return {}
              end
            }
          end
          package.loaded["runtime.configuration"] = nil
          package.loaded["presentation.availability"] = nil
          boot()

          local root = library.open(player, {tab = "availability"})
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "lead"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(loads == 1 and rows_calls >= 2,
            "Availability must reuse one parse-time effective configuration across refreshes")
        ''')

    def test_default_closed_then_query_selection_location_native_navigation_and_reload_rebuild(self):
        self.lua.execute('''
          boot()
          library.on_init(); library.on_configuration_changed(); library.on_load()
          assert(next(storage) == nil and library.subscription_needs() == false)
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          assert(root and player.shortcut_name == "mir-research-browser" and player.shortcut_toggled)
          assert(storage.mir_library.schema == 1 and storage.mir_library.players[1].query == ""
            and storage.mir_library.players[1].status == 1)
          library.on_gui_location_changed({player_index = 1, element = root,})
          root.location = {x = 91, y = 44}
          library.on_gui_location_changed({player_index = 1, element = root})
          local original_root = root
          local query = root["mir_library_filters"]["mir_library_query"]
          local original_query = query
          query.text = "gear"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          assert(root == original_root and root["mir_library_filters"]["mir_library_query"] == original_query)
          query.text = "gear wheel"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          assert(root == original_root and root["mir_library_filters"]["mir_library_query"] == original_query)
          local rows = research_content(root)["mir_library_results"]
          assert(#rows.items == 1 and rows.items[1] == "Iron gear wheel productivity")
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})
          root = player.gui.screen["mir_research_browser"]
          local state = storage.mir_library.players[1]
          assert(state.query == "gear wheel" and state.selected == gear.name and state.scroll == 1)
          assert(state.location.x == 91 and state.location.y == 44)
          local before = storage.mir_library
          library.on_load()
          assert(storage.mir_library == before)
          library.on_gui_click({player_index = 1, element = research_content(root)["mir_library_actions"]["mir_library_open_native"]})
          assert(player.opened_technology == gear and player.gui.screen["mir_research_browser"] == nil)
          assert(not player.shortcut_toggled)
          library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(root.location.x == 91 and root.location.y == 44)
          assert(research_content(root)["mir_library_results"].scrolled_to.index == 1)
          library.on_gui_click({player_index = 1, element = research_content(root)["mir_library_actions"]["mir_library_close"]})
          assert(player.gui.screen["mir_research_browser"] == nil and not player.shortcut_toggled)
        ''')

    def test_filters_and_foreign_events_are_bounded(self):
        self.lua.execute('''
          boot()
          library.on_gui_text_changed({player_index = 1, element = {valid = true, name = "foreign", text = "nope"}})
          assert(next(storage) == nil)
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local family = root["mir_library_filters"]["mir_library_family"]
          family.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          root = player.gui.screen["mir_research_browser"]
          assert(#research_content(root)["mir_library_results"].items == 1)
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil)
        ''')

    def test_translation_dispatch_is_open_connected_only_and_closed_callbacks_only_release(self):
        self.lua.execute('''
          boot()
          player.connected = false
          library.open(player)
          assert(#player.translation_requests == 0 and next(storage) == nil and library.subscription_needs() == false)
          library.close(player)

          player.connected = true
          library.open(player)
          assert(#player.translation_requests == 1 and library.subscription_needs())
          local gear_request = player.translation_requests[1].id
          library.close(player)
          assert(player.gui.screen["mir_research_browser"] == nil)
          library.on_translation_maintenance({tick = 1})
          assert(#player.translation_requests == 1 and library.subscription_needs())
          library.on_string_translated({player_index = 1, id = gear_request,
            translated = true, result = "Closed stale gear"})
          assert(library.subscription_needs() == false)
        ''')

    def test_all_view_scans_native_identities_once_and_family_change_invalidates_unissued_work(self):
        self.lua.execute('''
          boot()
          library.open(player)
          assert(#player.translation_requests == 1
            and player.translation_requests[1].localised == "Iron gear wheel productivity")
          local root = player.gui.screen["mir_research_browser"]
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "gear"
          library.on_gui_text_changed({player_index = 1, element = query})
          assert(#player.translation_requests == 1)

          local family = root["mir_library_filters"]["mir_library_family"]
          family.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          -- The first request remains a stale issued window; the all-family
          -- cache requests its current MIR row and actual foreign native row.
          assert(#player.translation_requests == 3)
          local old_id = player.translation_requests[1].id
          local all_gear = player.translation_requests[2].id
          local all_foreign = player.translation_requests[3].id
          library.on_string_translated({player_index = 1, id = old_id,
            translated = true, result = "old label"})
          library.on_string_translated({player_index = 1, id = all_gear,
            translated = true, result = "Gear translated"})
          library.on_string_translated({player_index = 1, id = all_foreign,
            translated = true, result = "Foreign translated"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_results"].items[1] == "Gear translated")
        ''')

    def test_all_view_native_translation_scan_is_bounded_before_request_dispatch(self):
        self.lua.execute('''
          boot()
          for index = 1, 30001 do
            local id = "native-" .. index
            player.force.technologies[id] = {valid = true, name = id, localised_name = id}
          end
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 0 and library.subscription_needs() == false)
        ''')
    def test_translation_callback_checks_live_scope_and_discards_vanished_root(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local id = player.translation_requests[1].id
          local root = player.gui.screen["mir_research_browser"]
          player.locale = "de"
          -- Native state may lead its locale-change event. The response frees
          -- the ID without applying the label to the stale cached scope.
          library.on_string_translated({player_index = 1, id = id,
            translated = true, result = "incorrect locale label"})
          assert(research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity")
          assert(library.subscription_needs() == false)
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 2)

          local locale_current = player.translation_requests[2].id
          player.force.index = 2
          library.on_string_translated({player_index = 1, id = locale_current,
            translated = true, result = "incorrect force label"})
          assert(research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity")
          library.on_player_changed_force({player_index = 1})
          assert(#player.translation_requests == 3)

          local current = player.translation_requests[3].id
          root = player.gui.screen["mir_research_browser"]
          root.destroy()
          library.on_string_translated({player_index = 1, id = current,
            translated = true, result = "rootless label"})
          local view = storage.mir_library.players[1]
          local open, pending = library.native_subscription_needs()
          assert(player.gui.screen["mir_research_browser"] == nil and library.subscription_needs() == false)
          assert(view.open == false and view.refresh_pending == false and not open and not pending,
            "late rootless callback retained a native Library subscription")
        ''')

    def test_vanished_root_locale_and_force_invalidations_retire_native_view_flags(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          root.destroy()
          library.on_player_locale_changed({player_index = 1})
          library.on_player_changed_force({player_index = 1})
          local view = storage.mir_library.players[1]
          local open, pending = library.native_subscription_needs()
          assert(view.open == false and view.refresh_pending == false and not open and not pending,
            "rootless locale or force invalidation retained a native Library subscription")
          assert(#player.translation_requests == 1 and library.subscription_needs(),
            "invalidating a vanished root released its durable native request")
        ''')

    def test_malformed_translation_sidecar_and_active_window_are_preserved_without_new_requests(self):
        self.lua.execute('''
          boot()
          local unknown = {version = "future", retained = {request = 99}}
          storage.mir_library = {schema = 1, players = {}, translations = unknown}
          library.open(player)
          assert(storage.mir_library.translations == unknown and #player.translation_requests == 0)

          boot()
          local malformed = {pending = {{request_id = "not-a-native-id"}}}
          local ledger = {schema = 1, next_epoch = 0, active = {[1] = malformed}, retired = {}}
          storage.mir_library = {schema = 1, players = {}, translations = ledger}
          library.open(player)
          assert(storage.mir_library.translations == ledger and ledger.active[1] == malformed)
          assert(#player.translation_requests == 0)
          library.on_translation_maintenance({tick = 1800})
          assert(ledger.active[1] == malformed and #player.translation_requests == 0)
        ''')
    def test_pending_translations_survive_locale_change_close_and_reload(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 2)
          player.locale = "de"
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 4)
          local pending = storage.mir_library.translations.active[1].pending
          assert(#pending == 4)
          local queue, current, progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          library.close(player)
          assert(storage.mir_library.translations.working == nil)
          package.loaded["runtime.library"] = nil
          library = require("runtime.library")
          library.on_load()
          library.open(player, {family = "all"})
          assert(#player.translation_requests == 6,
            "valid old/current translation requests prevented a reopened Library from dispatching")
          for index = 1, 4 do
            library.on_string_translated({player_index = 1,
              id = player.translation_requests[index].id, translated = true, result = "STALE"})
          end
          library.on_string_translated({player_index = 1, id = player.translation_requests[5].id,
            translated = true, result = "Zahnrad"})
          library.on_string_translated({player_index = 1, id = player.translation_requests[6].id,
            translated = true, result = "Fremde Forschung"})
          local root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_results"].items[1] == "Zahnrad")
          assert(not library.subscription_needs())
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress)
        ''')

    def test_warm_and_cold_translation_replies_produce_equal_saved_work_and_native_requests(self):
        self.lua.execute(r'''
          boot()
          for index=1,18 do
            local name="foreign-cold-probe-"..index
            player.force.technologies[name]={valid=true,name=name,level=1,researched=false,
              enabled=true,visible_when_disabled=false,localised_name=name,prototype={max_level=1}}
          end
          library.open(player,{family="all"})
          assert(#player.translation_requests==16)
          local function clone(value)
            if type(value)~="table" then return value end
            local copied={}; for key,child in pairs(value) do copied[key]=clone(child) end
            return copied
          end
          local function equal(left,right)
            if type(left)~=type(right) then return false end
            if type(left)~="table" then return left==right end
            for key,value in pairs(left) do if not equal(value,right[key]) then return false end end
            for key in pairs(right) do if left[key]==nil then return false end end
            return true
          end
          local before,requests,warm=clone(storage),clone(player.translation_requests),library
          package.loaded["runtime.library"]=nil
          local cold=require("runtime.library")
          local function reply(module)
            for index=1,8 do
              module.on_string_translated{player_index=1,id=requests[index].id,
                translated=true,result="translated-"..index}
            end
          end
          player.translation_requests={}
          reply(warm)
          local warm_state,warm_requests=clone(storage),clone(player.translation_requests)
          storage=clone(before)
          player.translation_requests={}; player.next_translation_id=16
          local available_game=game
          game=nil
          cold.on_load()
          assert(equal(storage,before),"on_load changed saved translation work")
          game=available_game
          reply(cold)
          assert(equal(storage,warm_state),"cache warmth changed durable translation work")
          assert(equal(player.translation_requests,warm_requests),"cache warmth changed native requests")
          assert(#player.translation_requests==4 and #storage.mir_library.translations.active[1].pending==12)
        ''')

    def test_completed_open_translation_work_survives_load_and_is_retired_on_close(self):
        self.lua.execute(r'''
          boot()
          local root=library.open(player,{family="all"})
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result=index==1 and "Zahnrad" or "Fremde Forschung"}
          end
          assert(not library.subscription_needs())
          local ledger=storage.mir_library.translations
          local saved_cache=ledger.working[1].cache
          local epoch=ledger.next_epoch
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local available_game=game; game=nil
          library.on_load()
          assert(ledger.working[1].cache==saved_cache and ledger.next_epoch==epoch)
          game=available_game
          assert(library.open(player)==root and #player.translation_requests==2 and ledger.next_epoch==epoch)
          assert(research_content(root)["mir_library_results"].items[1]=="Zahnrad")
          library.close(player)
          assert(ledger.working==nil and ledger.active[1]==nil and not library.subscription_needs())
        ''')

    def test_issued_only_legacy_translation_sidecar_loads_read_only_and_drains_without_reissue(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          local ledger=storage.mir_library.translations
          -- Pre-correction MIR5 saved only issued IDs, without a working map.
          ledger.working=nil
          local pending=ledger.active[1].pending
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          local available_game=game; game=nil
          library.on_load()
          assert(ledger.working==nil and ledger.active[1].pending==pending)
          game=available_game
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result="old-window"}
          end
          assert(ledger.working==nil and not library.subscription_needs() and #player.translation_requests==2)
          library.open(player,{family="all"})
          assert(#player.translation_requests==4 and ledger.working[1].schema==1)
        ''')

    def test_translation_maintenance_orders_open_players_before_issuing_native_retries(self):
        self.lua.execute(r'''
          boot()
          local order,next_id={},100
          player.request_translation=function() order[#order+1]=1;next_id=next_id+1;return next_id end
          local second={valid=true,index=2,locale="de",connected=true,force=player.force,
            gui={screen=gui_container(nil)},set_shortcut_toggled=function() end,
            request_translation=function() order[#order+1]=2;next_id=next_id+1;return next_id end}
          game.get_player=function(index) return index==1 and player or index==2 and second or nil end
          library.open(player,{family="all"}); library.open(second,{family="all"})
          setmetatable(storage.mir_library.translations.active,{__pairs=function(rows)
            local index=3
            return function() index=index-1;if index>0 then return index,rows[index] end end
          end})
          order={}
          library.on_translation_maintenance{tick=1800}
          assert(table.concat(order,",")=="1,1,2,2","native request order follows active-map traversal")
        ''')

    def test_configuration_invalidates_a_saved_open_working_cache_without_prior_on_load(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          for index=1,2 do
            library.on_string_translated{player_index=1,id=player.translation_requests[index].id,
              translated=true,result="old-configuration"}
          end
          local ledger=storage.mir_library.translations
          local old_cache,epoch=ledger.working[1].cache,ledger.next_epoch
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          library.on_configuration_changed()
          assert(ledger.working[1].cache~=old_cache and ledger.next_epoch>epoch)
          assert(#player.translation_requests==4)
          assert(research_content(player.gui.screen["mir_research_browser"])["mir_library_results"].items[1]
            =="Iron gear wheel productivity","configuration retained old translated labels")
        ''')

    def test_unknown_saved_translation_work_is_preserved_and_cannot_issue_another_window(self):
        self.lua.execute(r'''
          boot()
          library.open(player,{family="all"})
          local ledger=storage.mir_library.translations
          local unknown={schema=77,cache={pending={99}}}
          ledger.working[1]=unknown
          package.loaded["runtime.library"]=nil
          library=require("runtime.library")
          library.on_load()
          library.open(player,{family="all"})
          assert(ledger.working[1]==unknown and #player.translation_requests==2)
          library.close(player)
          assert(ledger.working[1]==unknown and library.subscription_needs())
        ''')

    def test_translation_stale_scope_reload_and_reused_index_never_publish_old_labels(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          local old_gear = player.translation_requests[1].id
          local old_foreign = player.translation_requests[2].id
          player.locale = "de"
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 4)
          local locale_gear = player.translation_requests[3].id
          local locale_foreign = player.translation_requests[4].id
          library.on_string_translated({player_index = 1, id = old_gear,
            translated = true, result = "OLD GEAR"})
          library.on_string_translated({player_index = 1, id = old_foreign,
            translated = true, result = "OLD FOREIGN"})
          local root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity")

          player.force.index = 2
          library.on_player_changed_force({player_index = 1})
          assert(#player.translation_requests == 6)
          local force_gear = player.translation_requests[5].id
          local force_foreign = player.translation_requests[6].id
          library.on_string_translated({player_index = 1, id = locale_gear,
            translated = true, result = "STALE LOCALE GEAR"})
          library.on_string_translated({player_index = 1, id = locale_foreign,
            translated = true, result = "STALE LOCALE FOREIGN"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity")
          library.on_string_translated({player_index = 1, id = force_gear,
            translated = true, result = "Zahnrad"})
          library.on_string_translated({player_index = 1, id = force_foreign,
            translated = true, result = "Fremde Forschung"})
          root = player.gui.screen["mir_research_browser"]
          assert(research_content(root)["mir_library_results"].items[1] == "Zahnrad")

          local saved = storage.mir_library
          local reload_gear, reload_foreign = force_gear, force_foreign
          library.close(player)
          library.open(player)
          reload_gear, reload_foreign = player.translation_requests[7].id, player.translation_requests[8].id
          package.loaded["runtime.library"] = nil
          library = require("runtime.library")
          library.on_load()
          assert(storage.mir_library == saved and library.subscription_needs())
          library.on_string_translated({player_index = 1, id = reload_gear,
            translated = true, result = "late"})
          library.on_string_translated({player_index = 1, id = reload_foreign,
            translated = true, result = "late"})
          assert(library.subscription_needs() == false)

          assert(#player.translation_requests == 8
            and research_content(player.gui.screen["mir_research_browser"])["mir_library_results"].items[1] == "late",
            "same-scope callbacks were not restored consistently across load")
          -- A later explicit close/open starts the separate request lifetime
          -- used by the removed/reused-player regression below.
          library.close(player)
          library.open(player)
          local removed_gear, removed_foreign = player.translation_requests[9].id, player.translation_requests[10].id
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil and library.subscription_needs())

          local prior_requests = #player.translation_requests
          screen = gui_container(nil)
          player = {
            valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
            force = {index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
              research_queue = {}, current_research = nil},
            translation_requests = {}, next_translation_id = 100
          }
          player.set_shortcut_toggled = function() end
          player.request_translation = function(localised)
            player.next_translation_id = player.next_translation_id + 1
            player.translation_requests[#player.translation_requests + 1] = {id = player.next_translation_id, localised = localised}
            return player.next_translation_id
          end
          library.open(player)
          assert(#player.translation_requests == 0)
          library.on_translation_maintenance({tick = 1800})
          assert(#player.translation_requests == 1 and library.subscription_needs())
        ''')

    def test_retired_translation_callbacks_resume_an_open_reused_player_without_publishing_old_labels(self):
        self.lua.execute('''
          boot()
          library.open(player, {family = "all"})
          local old_gear, old_foreign = player.translation_requests[1].id, player.translation_requests[2].id
          library.on_player_removed({player_index = 1})
          assert(storage.mir_library.players[1] == nil and library.subscription_needs())

          screen = gui_container(nil)
          player = {
            valid = true, index = 1, locale = "en", connected = true, gui = {screen = screen},
            force = {index = 1, technologies = {[gear.name] = gear, [foreign.name] = foreign},
              research_queue = {}, current_research = nil},
            translation_requests = {}, next_translation_id = 100
          }
          player.set_shortcut_toggled = function() end
          player.request_translation = function(localised)
            player.next_translation_id = player.next_translation_id + 1
            local request = {id = player.next_translation_id, localised = localised}
            player.translation_requests[#player.translation_requests + 1] = request
            return request.id
          end
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          assert(#player.translation_requests == 0 and root ~= nil,
            "reused index issued while retired native IDs remained")

          library.on_string_translated({player_index = 1, id = old_gear,
            translated = true, result = "old player gear"})
          assert(#player.translation_requests == 0
            and research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity")
          library.on_string_translated({player_index = 1, id = old_foreign,
            translated = true, result = "old player foreign"})
          assert(#player.translation_requests == 1 and player.translation_requests[1].id == 101,
            "last retired callback did not resume the already open replacement player")
          assert(research_content(root)["mir_library_results"].items[1] == "Iron gear wheel productivity",
            "retired callback published into the replacement player's view")
        ''')

    def test_status_filter_persists_read_only_queue_context_and_cap_explanation(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local status = root["mir_library_filters"]["mir_library_status"]
          status.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = status})

          root = player.gui.screen["mir_research_browser"]
          local state = storage.mir_library.players[1]
          assert(state.status == 4 and root["mir_library_filters"]["mir_library_status"].selected_index == 4)
          local rows = research_content(root)["mir_library_results"]
          assert(#rows.items == 1 and rows.items[1] == "Iron gear wheel productivity")
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})

          root = player.gui.screen["mir_research_browser"]
          local detail = research_content(root)["mir_library_detail"]
          local context = detail["mir_library_detail_context"]
          assert(context["mir_library_context_status"].caption[1] == "mir-browser.context-status")
          assert(context["mir_library_context_current"].caption[1] == "mir-browser.context-current")
          assert(context["mir_library_context_queue_count"].caption[1] == "mir-browser.context-queue-count"
            and context["mir_library_context_queue_count"].caption[2] == 1)
          assert(context["mir_library_context_queue_position"].caption[1] == "mir-browser.context-queue-position"
            and context["mir_library_context_queue_position"].caption[2] == 1)
          assert(context["mir_library_context_queue_guidance"].caption[1] == "mir-browser.native-queue-guidance")
          assert(detail["mir_library_detail_cap"].caption[1] == "mir-browser.cap-finite")

          local queue, current, progress = player.force.research_queue, player.force.current_research, player.force.research_progress
          local saved = storage.mir_library
          library.on_load()
          assert(storage.mir_library == saved and storage.mir_library.players[1].status == 4)
          library.close(player)
          library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(root["mir_library_filters"]["mir_library_status"].selected_index == 4)
          assert(player.force.research_queue == queue and player.force.current_research == current
            and player.force.research_progress == progress)
        ''')

    def test_foreign_same_named_root_and_children_never_create_preferences_or_receive_callbacks(self):
        self.lua.execute('''
          boot()
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          local filters = foreign.add{type = "flow", name = "mir_library_filters"}
          local query = filters.add{type = "textfield", name = "mir_library_query", text = "foreign text"}
          local family = filters.add{type = "drop-down", name = "mir_library_family", selected_index = 2}
          local status = filters.add{type = "drop-down", name = "mir_library_status", selected_index = 4}
          local content = foreign.add{type = "flow", name = "mir_library_content"}
          local results = content.add{type = "list-box", name = "mir_library_results", selected_index = 1}
          local actions = content.add{type = "flow", name = "mir_library_actions"}
          local close = actions.add{type = "button", name = "mir_library_close"}
          local open_native = actions.add{type = "button", name = "mir_library_open_native"}
          foreign.location = {x = 17, y = 29}

          -- Ordinary entry points see the collision, leave it alone, and do
          -- not allocate a private player preference merely to reject it.
          assert(library.open(player) == nil)
          library.close(player)
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          assert(next(storage) == nil and foreign.valid)
          assert(player.gui.screen["mir_research_browser"] == foreign and player.shortcut_toggled == nil)

          -- Every routed GUI callback must prove the tagged root and all of
          -- its ancestors, rather than accepting a globally shared name.
          query.text = "attempted mutation"
          library.on_gui_text_changed({player_index = 1, element = query})
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          library.on_gui_selection_state_changed({player_index = 1, element = status})
          library.on_gui_selection_state_changed({player_index = 1, element = results})
          library.on_gui_click({player_index = 1, element = close})
          library.on_gui_click({player_index = 1, element = open_native})
          library.on_gui_location_changed({player_index = 1, element = foreign})
          library.on_gui_closed({player_index = 1, element = foreign})
          assert(next(storage) == nil and foreign.valid)
          assert(query.text == "attempted mutation" and family.selected_index == 2 and status.selected_index == 4)
          assert(player.gui.screen["mir_research_browser"] == foreign and player.opened_technology == nil)
        ''')

    def test_cap_provider_is_configured_without_force_extension_or_periodic_work(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()
          cap_calls = 0
          library.set_cap_provider(function(actual_force)
            assert(actual_force == player.force)
            cap_calls = cap_calls + 1
            return {[gear.name] = 2}
          end)
          library.on_load()
          assert(cap_calls == 0 and library.subscription_needs() == false)
          library.open(player)
          local root = player.gui.screen["mir_research_browser"]
          local detail = research_content(root)["mir_library_detail"]
          assert(cap_calls == 1 and detail["mir_library_detail_cap"] == nil)
          local rows = research_content(root)["mir_library_results"]
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})
          root = player.gui.screen["mir_research_browser"]
          detail = research_content(root)["mir_library_detail"]
          assert(cap_calls == 2)
          assert(detail["mir_library_detail_level"].caption[1] == "mir-browser.level-cap")
          assert(detail["mir_library_detail_cap"].caption[1] == "mir-browser.cap-finite"
            and detail["mir_library_detail_cap"].caption[2] == 2
            and detail["mir_library_detail_cap"].caption[3] == "ips-max-level-research_gears")
          local ok = pcall(function() library.set_cap_provider("not a function") end)
          assert(not ok)
        ''')

    def test_native_navigation_rejects_missing_selection_before_native_technology_lookup(self):
        self.lua.execute('''
          boot()
          library.open(player)
          local original_force = player.force
          player.force = setmetatable({}, {__index = function(_, key)
            error("missing selection read native force field: " .. tostring(key))
          end})
          library.on_gui_click({player_index = 1,
            element = {valid = true, name = "mir_library_open_native"}})
          assert(player.opened_technology == nil)
          player.force = original_force
        ''')

    def test_real_catalogue_and_model_handoff_filters_the_native_gear_row(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          script = {active_mods={base="2.1.23"}}
          boot()
          -- Native callbacks cannot import modules, including cached ones.
          require = function(name) error("Library callback imported " .. name) end
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "research_gears"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          local results = research_content(root)["mir_library_results"]
          assert(#results.items == 1 and results.items[1] == "recipe-prod-research_gears-1")
          results.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = results})
          assert(storage.mir_library.players[1].selected == gear.name)
          assert(research_content(player.gui.screen["mir_research_browser"])["mir_library_detail"] ~= nil)
        ''')

    def _assert_real_selected_catalogue_opens_without_runtime_imports(self, profile_name, target_id, expected_id):
        editions = json.loads((ROOT / "targets/editions.json").read_text(encoding="utf-8"))["targets"]
        profile = json.loads((ROOT / f"tests/profiles/{profile_name}.json").read_text(encoding="utf-8"))
        target = self.lua.table_from(editions[target_id])
        target["id"] = target_id
        self.lua.globals().selected_target = target
        self.lua.globals().selected_mods = self.lua.table_from({
            mod["name"]: mod["version"] for mod in profile["mods"] if mod["enabled"]
        })
        self.lua.globals().expected_id = expected_id
        self.lua.execute(r'''
          package.loaded["platform.target"] = selected_target
          script, mods = {active_mods=selected_mods}, selected_mods
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          package.loaded["runtime.library"] = nil

          -- control.lua parsing: real selected adapters and their
          -- declarations load before Factorio begins callbacks.
          boot()
          local catalogue = package.loaded["research.catalogue"]
          local modern = package.loaded["compatibility.modern_catalogue"]
          assert(type(catalogue) == "table" and type(modern) == "table")
          local before = catalogue.declared()
          local found = false
          for _, row in ipairs(before) do
            if row.id == expected_id then found = true end
          end
          assert(found, "selected closure omitted " .. expected_id)

          local select, selections = modern.select, 0
          modern.select = function(...)
            selections = selections + 1
            return select(...)
          end
          -- Factorio rejects every require after parsing, including a
          -- cached module.  Library.open must consume its parsed rows.
          require = function(name) error("post-parse require: " .. tostring(name)) end

          before[1].id = "foreign"
          local after = catalogue.declared()
          assert(after[1].id == "recipe-prod-research_gears-1",
            "Library catalogue returned caller-owned rows")
          local root = library.open(player, {selected=gear.name})
          assert(root == player.gui.screen["mir_research_browser"]
            and storage.mir_library.players[1].selected == gear.name)
          assert(selections == 0, "Library rebuilt selected adapters after parsing")
        ''')

    def test_real_space_age_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "space-age-f210-2123", "f210", "recipe-prod-research_agricultural_growth_speed-1")

    def test_real_py_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "py-coal-f200-2077", "f200", "recipe-prod-research_material_py_log-1")

    def test_real_bob_core_catalogue_opens_without_runtime_imports(self):
        self._assert_real_selected_catalogue_opens_without_runtime_imports(
            "bob-core-f210-2123", "f210", "recipe-prod-research_material_tin-1")

    def test_level_modes_filter_real_native_rows_and_preserve_owned_personal_state(self):
        self.lua.execute('''
          package.preload["research.catalogue"], package.preload["presentation.library_model"] = nil, nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          local native_queue, native_current = player.force.research_queue, player.force.current_research
          library.open(player, {family = "all", mode = 2, page = 7})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          local filters, content = root["mir_library_filters"], research_content(root)
          local query, mode = filters["mir_library_query"], filters["mir_library_mode"]
          assert(view.mode == 2 and view.page == 7 and mode.selected_index == 2)
          assert(#content["mir_library_results"].items == 1
            and content["mir_library_results"].items[1] == foreign.name)

          mode.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = mode})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 1 and view.scroll == 1)
          assert(filters["mir_library_query"] == query and filters["mir_library_mode"] == mode)
          assert(#content["mir_library_results"].items == 1
            and content["mir_library_results"].items[1] == gear.name)

          library.open(player, {page = 7})
          for _, invalid in ipairs({0, 4, 1.5, "2", 0/0}) do
            library.open(player, {mode = invalid})
            view = storage.mir_library.players[1]
            assert(view.mode == 3 and view.page == 7, "invalid mode reset accepted state")
          end
          local foreign_root = player.gui.screen.add{type = "frame", name = "foreign-frame"}
          local foreign_filters = foreign_root.add{type = "flow", name = "mir_library_filters"}
          local spoof = foreign_filters.add{type = "drop-down", name = "mir_library_mode", selected_index = 1}
          library.on_gui_selection_state_changed({player_index = 1, element = spoof})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 7, "foreign GUI changed the personal mode")
          mode.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = mode})
          view = storage.mir_library.players[1]
          assert(view.mode == 3 and view.page == 7)

          library.close(player); library.on_load(); library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(root["mir_library_filters"]["mir_library_mode"].selected_index == 3
            and storage.mir_library.players[1].mode == 3)
          -- Published modes classify an effective capped infinity as finite.
          library.set_cap_provider(function() return {[gear.name] = 2} end)
          library.open(player, {mode = 2})
          assert(#research_content(root)["mir_library_results"].items == 2)
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == .5 and gear.level == 3 and gear.enabled == false)
        ''')

    def test_historical_filter_order_hidden_page_and_selection_options_drive_real_library_state(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = nil
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"] = nil
          package.loaded["presentation.library_model"] = nil
          boot()

          library.open(player, {family = "all", status = 1, sort = "name-desc", page = 7,
            selected = gear.name})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          assert(view.family == "all" and view.status == 1 and view.sort == "name-desc"
            and view.stable_sort == "progression" and view.page == 7
            and next(view.hidden) == nil and view.selected == gear.name)
          assert(root["mir_library_filters"]["mir_library_sort"].selected_index == 4)
          local rows = research_content(root)["mir_library_results"]
          assert(#rows.items == 2 and rows.items[1] == gear.name and rows.items[2] == foreign.name)

          -- The historical page value survives reopening, but it was never a
          -- player-list paginator: the continuous list retains both rows.
          library.close(player)
          library.open(player)
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = research_content(root)["mir_library_results"]
          assert(view.page == 7 and #rows.items == 2
            and rows.items[1] == gear.name and rows.items[2] == foreign.name)

          -- The valid dense remote list changes actual rendering and an
          -- explicit valid page wins over the normal filter page reset.
          library.open(player, {hidden = {foreign.name}, page = 7})
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = research_content(root)["mir_library_results"]
          assert(view.hidden[foreign.name] and view.page == 7
            and #rows.items == 1 and rows.items[1] == gear.name)

          -- Invalid remote-style values leave each previously accepted field
          -- untouched, including unknown selected and hidden technologies.
          library.open(player, {status = 5, sort = "invalid", page = 30001,
            selected = "unknown", hidden = {gear.name, "unknown"}})
          view = storage.mir_library.players[1]
          assert(view.status == 1 and view.sort == "name-desc" and view.page == 7
            and view.selected == gear.name and view.hidden[foreign.name]
            and not view.hidden[gear.name])

          -- A real filter operation resets the persisted historical page; the
          -- continuous current list deliberately does not pretend to paginate.
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "research_gears"
          library.on_gui_text_changed({player_index = 1, element = query})
          view = storage.mir_library.players[1]
          assert(view.page == 1 and view.query == "research_gears")

          root = player.gui.screen["mir_research_browser"]
          local sort = root["mir_library_filters"]["mir_library_sort"]
          sort.selected_index = 2
          library.on_gui_selection_state_changed({player_index = 1, element = sort})
          view = storage.mir_library.players[1]
          assert(view.sort == "native" and view.stable_sort == "native" and view.page == 1)

          local status = root["mir_library_filters"]["mir_library_status"]
          status.selected_index = 4
          library.on_gui_selection_state_changed({player_index = 1, element = status})
          view = storage.mir_library.players[1]
          assert(view.status == 4 and view.page == 1)
        ''')

    def test_real_model_host_preserves_hidden_visibility_and_full_family_callbacks(self):
        self.lua.execute('''
          package.preload["research.catalogue"] = function()
            return {declared = function()
              return {
                {id = "recipe-prod-research_gears-1", family = "research_gears", progression = 1,
                  native_order = "p[research_gears]"},
                {id = "agricultural-growth-speed", family = "research_agricultural_growth_speed", progression = 2,
                  native_order = "p[agricultural-growth-speed]"},
                {id = "spoilage-preservation", family = "research_spoilage_preservation", progression = 3,
                  native_order = "p[spoilage-preservation]"}
              }
            end}
          end
          package.preload["presentation.library_model"] = nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          local native_queue, native_current = player.force.research_queue, player.force.current_research

          gear.localised_name = {"technology-name.more-infinite-research.research_gears", "Iron gear wheel"}
          -- The actual model receives authored descriptor metadata. Its gear
          -- selector is declaration-only: the foreign force row must not
          -- leak into it or cause a native catalogue traversal.
          library.open(player, {family = "research_gears", page = 7})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          local filters, content = root["mir_library_filters"], research_content(root)
          local family, visibility = filters["mir_library_family"], filters["mir_library_visibility"]
          assert(view.family == "research_gears" and view.visibility == 1 and view.page == 7)
          assert(family.selected_index == 5 and visibility.selected_index == 1)
          assert(family.items[5] == gear.localised_name,
            "authored family caption dropped the complete native localization parameters")
          assert(#player.translation_requests == 1)
          assert(#content["mir_library_results"].items == 1
            and content["mir_library_results"].items[1] == gear.name)

          library.close(player); library.on_load(); library.open(player)
          root = player.gui.screen["mir_research_browser"]
          filters, content = root["mir_library_filters"], research_content(root)
          family, visibility = filters["mir_library_family"], filters["mir_library_visibility"]
          assert(storage.mir_library.players[1].family == "research_gears"
            and filters["mir_library_family"].selected_index == 5
            and #content["mir_library_results"].items == 1
            and content["mir_library_results"].items[1] == gear.name)

          -- External is the published native scope. It is the only selector
          -- here that includes the actual foreign technology.
          family = filters["mir_library_family"]
          family.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.page == 1
            and #content["mir_library_results"].items == 1
            and content["mir_library_results"].items[1] == foreign.name)

          -- Remote-style input stays strict and cannot replace a persisted
          -- hidden-only selection or its explicitly retained page.
          library.open(player, {hidden = {foreign.name}, visibility = 2, page = 7})
          for _, invalid in ipairs({0, 4, 1.5, "2", 0/0}) do
            library.open(player, {visibility = invalid})
            view = storage.mir_library.players[1]
            assert(view.visibility == 2 and view.page == 7)
          end
          library.open(player, {family = "unknown-family"})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.visibility == 2 and view.page == 7)
          local foreign_root = player.gui.screen.add{type = "frame", name = "foreign-visibility-frame"}
          local foreign_filters = foreign_root.add{type = "flow", name = "mir_library_filters"}
          local spoof = foreign_filters.add{type = "drop-down", name = "mir_library_visibility", selected_index = 1}
          library.on_gui_selection_state_changed({player_index = 1, element = spoof})
          view = storage.mir_library.players[1]
          assert(view.visibility == 2 and view.page == 7, "foreign GUI changed hidden visibility")
          visibility.selected_index = 3
          library.on_gui_selection_state_changed({player_index = 1, element = visibility})
          view = storage.mir_library.players[1]
          assert(view.visibility == 3 and view.page == 1)
          assert(research_content(root)["mir_library_availability_empty"] == nil)
          assert(research_content(root)["mir_library_availability_1"].caption[2][1]
              == "technology-name.more-infinite-research.research_agricultural_growth_speed"
            and research_content(root)["mir_library_availability_2"].caption[2][1]
              == "technology-name.more-infinite-research.research_spoilage_preservation")
          family.selected_index = 7
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.page == 1, "invalid owned family was accepted")

          visibility.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = visibility})
          view = storage.mir_library.players[1]
          assert(view.visibility == 1 and view.page == 1 and view.scroll == 1)
          assert(#content["mir_library_results"].items == 0)
          assert(player.force.research_queue == native_queue and player.force.current_research == native_current
            and player.force.research_progress == .5 and gear.level == 3 and gear.enabled == false)
        ''')

    def test_configuration_migrates_published_browser_view_without_dropping_later_fidelity_fields(self):
        self.lua.execute(r'''
          package.preload["research.catalogue"], package.preload["presentation.library_model"] = nil, nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          -- Independent captured schema-3 shape from the published 4.7 browser.
          -- These values are deliberately not derived from MIR5 migration code.
          local historical = {
            schema = 3, mode = 3, status = 2, page = 7, search = "historical gear",
            tab = "settings", setting_selection = "ips-cost-base-research_gears",
            settings_scope = "options", effect_page = 4, family = "all",
            sort = "name-asc", stable_sort = "native", settings_search = "cost tuning",
            visibility = 2, selected = gear.name, location = {x = 12, y = 19},
            scroll = 6, hidden = {["foreign-research"] = true},
            geometry = {width = 900, height = 700},
            report_settings = false, report_omissions = true,
            report_destination = "script-output/browser-1-42.txt"
          }
          local published_availability = {schema = 3, tab = "research", visibility = 3,
            family = "mir", mode = 1, status = 1, page = 1, sort = "progression"}
          storage.mir = {research_browser = {players = {
            [1] = historical, [2] = published_availability
          }}}
          local old = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          old.location = {x = 55, y = 66}
          old.add{type = "tabbed-pane", name = "mir_browser_tabs"}

          library.on_configuration_changed()

          local state = storage.mir_library
          local view = state.players[1]
          assert(view.query == "historical gear" and view.family == "all" and view.status == 2 and view.mode == 3)
          assert(view.selected == gear.name and view.scroll == 6 and view.page == 7 and view.visibility == 2)
          assert(view.sort == "name-asc" and view.stable_sort == "native"
            and view.hidden["foreign-research"])
          assert(view.tab == "settings" and view.settings_scope == "options"
            and view.settings_query == "cost tuning" and view.setting_selected == "ips-cost-base-research_gears")
          assert(state.players[2].tab == "research" and state.players[2].visibility == 3)
          -- The currently open published frame location wins over its stale
          -- persisted location, as the old browser itself did on close.
          assert(view.location.x == 55 and view.location.y == 66)
          assert(storage.mir.research_browser.players[1] == historical)
          local preserved = state.legacy_browser
          assert(preserved.version == 1 and preserved.source == "storage.mir.research_browser")
          assert(preserved.authoritative_source == "storage.mir.research_browser")
          assert(preserved.snapshot_status[1].complete and not preserved.snapshot_status[1].truncated)
          assert(preserved.players[2].visibility == 3)
          local saved = preserved.players[1]
          assert(saved.mode == 3 and saved.status == 2 and saved.page == 7)
          assert(saved.tab == "settings" and saved.settings_scope == "options")
          assert(saved.sort == "name-asc" and saved.stable_sort == "native")
          assert(saved.settings_search == "cost tuning" and saved.visibility == 2)
          assert(saved.hidden["foreign-research"] and saved.geometry.width == 900)
          assert(saved.report_settings == false and saved.report_omissions == true)
          assert(old.valid == false)
          local root = player.gui.screen["mir_research_browser"]
          assert(root and root ~= old and root["mir_library_filters"] and root["mir_library_tabs"] and research_content(root))
          assert(player.shortcut_toggled == true)
        ''')

    def test_delivered_tabs_show_effective_startup_settings_and_keep_native_queue_authoritative(self):
        self.lua.execute(r'''
          boot()
          helpers = {
            encode_string = function(text) return text end,
            decode_string = function(text) return text end,
            json_to_table = function(text)
              if text == "library-profile" then return {
                schema = 1, kind = "mir-settings-profile", settings = {
                  ["ips-cost-base-research_gears"] = 777
                }
              } end
            end
          }
          settings = {startup = {
            ["ips-enable-research_gears"] = {value = false},
            ["ips-cost-base-research_gears"] = {value = 4242},
            ["mir-settings-profile-import"] = {value = "MIRSET1:library-profile"}
          }}
          library.open(player, {tab = "settings", settings_scope = "research", settings_search = "research_gears"})
          local root = player.gui.screen["mir_research_browser"]
          local tabs = root["mir_library_tabs"]
          assert(tabs.type == "tabbed-pane" and #tabs._tabs == 4 and tabs.selected_tab_index == 3)
          local settings_content = tabs["mir_library_settings_content"]
          local settings_dynamic = settings_content["mir_library_settings_dynamic"]
          assert(storage.mir_library.players[1].tab == "settings"
            and settings_dynamic["mir_library_settings_count"].caption[1] == "mir-browser.settings-count")
          local enabled = settings_dynamic["mir_library_settings_detail"]["mir_library_setting_1_value"]
          assert(enabled.caption[1] == "mir-browser.setting-off"
            and enabled.tooltip[2][1] == "mir-browser.setting-off"
            and enabled.tooltip[3][1] == "mir-browser.setting-on"
            and enabled.tooltip[4][1] == "mir-browser.source-direct")
          local cost = settings_dynamic["mir_library_settings_detail"]["mir_library_setting_2_value"]
          assert(cost.caption == "777" and cost.tooltip[1] == "mir-browser.setting-provenance"
            and cost.tooltip[2] == "4242" and cost.tooltip[4][1] == "mir-browser.source-mirset1")
          local settings_query = settings_content["mir_library_settings_query"]
          settings_query.text = "gears"
          library.on_gui_text_changed({player_index = 1, element = settings_query})
          assert(settings_content["mir_library_settings_query"] == settings_query
            and settings_query.valid and settings_query.text == "gears")
          local settings_list = settings_dynamic["mir_library_settings_list"]
          settings_list.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = settings_list})
          assert(storage.mir_library.players[1].setting_selected == "research_gears"
            and settings_content["mir_library_settings_query"] == settings_query)
          assert(#player.translation_requests == 0)

          tabs.selected_tab_index = 2
          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          local queue = tabs["mir_library_queue_content"]
          assert(storage.mir_library.players[1].tab == "queue"
            and #queue["mir_library_queue_list"].items == 1)
          local original_queue, original_current, original_progress = player.force.research_queue,
            player.force.current_research, player.force.research_progress
          queue["mir_library_queue_list"].selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = queue["mir_library_queue_list"]})
          assert(storage.mir_library.players[1].tab == "research"
            and storage.mir_library.players[1].selected == gear.name)
          assert(player.force.research_queue == original_queue and player.force.current_research == original_current
            and player.force.research_progress == original_progress)

          -- Published callers could still request Availability. It routed to
          -- Research's third visibility choice rather than a fifth tab.
          library.open(player, {tab = "availability"})
          assert(storage.mir_library.players[1].tab == "research"
            and storage.mir_library.players[1].visibility == 3)
          assert(research_content(root)["mir_library_availability_empty"] == nil)
          assert(research_content(root)["mir_library_availability_1"] ~= nil
            and research_content(root)["mir_library_availability_2"] ~= nil)
          tabs.selected_tab_index = 4
          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          assert(tabs["mir_library_help_content"]["mir_library_help_summary"].caption[1]
            == "mir-browser.help-summary")
        ''')

    def test_new_tab_and_settings_callbacks_do_not_claim_an_unowned_gui(self):
        self.lua.execute(r'''
          boot()
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          local tabs = foreign.add{type = "tabbed-pane", name = "mir_library_tabs"}
          tabs.selected_tab_index = 2
          local settings_content = tabs.add{type = "flow", name = "mir_library_settings_content"}
          local settings_query = settings_content.add{type = "textfield", name = "mir_library_settings_query", text = "foreign"}
          local settings_list = settings_content.add{type = "list-box", name = "mir_library_settings_list", selected_index = 1}
          local toolbar = settings_content.add{type = "flow", name = "mir_library_settings_toolbar"}
          local options = toolbar.add{type = "button", name = "mir_library_settings_options"}
          local queue_content = tabs.add{type = "flow", name = "mir_library_queue_content"}
          local queue_list = queue_content.add{type = "list-box", name = "mir_library_queue_list", selected_index = 1}

          library.on_gui_selected_tab_changed({player_index = 1, element = tabs})
          library.on_gui_text_changed({player_index = 1, element = settings_query})
          library.on_gui_selection_state_changed({player_index = 1, element = settings_list})
          library.on_gui_selection_state_changed({player_index = 1, element = queue_list})
          library.on_gui_click({player_index = 1, element = options})
          assert(next(storage) == nil and foreign.valid and settings_query.text == "foreign")
        ''')

    def test_configuration_marks_a_bounded_legacy_snapshot_without_mutating_its_authoritative_bucket(self):
        self.lua.execute(r'''
          boot()
          local historical = {schema = 3, search = "old", family = "all"}
          for index = 1, 600 do historical["retained-" .. index] = index end
          storage.mir = {research_browser = {players = {[1] = historical}}}

          library.on_configuration_changed()

          local preserved = storage.mir_library.legacy_browser
          local status = preserved.snapshot_status[1]
          assert(preserved.authoritative_source == "storage.mir.research_browser")
          assert(not status.complete and status.truncated and status.entry_limited)
          -- The exact historical record remains the full-fidelity authority.
          assert(storage.mir.research_browser.players[1] == historical)
          assert(historical["retained-600"] == 600)
        ''')

    def test_configuration_preserves_newer_private_view_and_does_not_claim_same_named_foreign_root(self):
        self.lua.execute(r'''
          boot()
          storage.mir_library = {
            schema = 1,
            players = {[1] = {
              schema = 1, query = "newer private query", family = "mir",
              selected = nil, location = {x = 7, y = 8}, scroll = 3
            }}
          }
          local historical = {
            schema = 3, mode = 1, status = 1, page = 1, search = "old query",
            tab = "research", family = "external", sort = "progression",
            stable_sort = "progression", settings_search = "", visibility = 1,
            selected = gear.name, location = {x = 10, y = 20}, scroll = 9
          }
          storage.mir = {research_browser = {players = {[1] = historical}}}
          local foreign = player.gui.screen.add{type = "frame", name = "mir_research_browser"}
          foreign.add{type = "flow", name = "unrelated_same_named_child"}

          library.on_configuration_changed()

          local view = storage.mir_library.players[1]
          assert(view.query == "newer private query" and view.family == "mir" and view.status == 1)
          assert(view.location.x == 7 and view.location.y == 8 and view.scroll == 3)
          assert(storage.mir_library.legacy_browser.players[1].family == "external")
          assert(foreign.valid and player.gui.screen["mir_research_browser"] == foreign)
          assert(player.shortcut_toggled == nil)
        ''')

    def test_source_keeps_event_registration_and_old_compiler_outside_the_slice(self):
        source = (ROOT / "source/runtime/library.lua").read_text()
        self.assertNotIn("script.on_event", source)
        self.assertNotIn("script.on_nth_tick", source)
        self.assertNotIn("remote.add_interface", source)
        self.assertNotIn("prototypes.mir", source)
        self.assertNotIn("force.caps", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("force.research_queue =", source)
        self.assertNotIn("force.add_research", source)
        self.assertNotIn("force.cancel_current_research", source)
        bootstrap = (ROOT / "source/runtime/bootstrap.lua").read_text()
        self.assertIn("on_library_tab_changed", bootstrap)
        self.assertIn("on_gui_selected_tab_changed", bootstrap)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryTests))
    sys.exit(0 if result.wasSuccessful() else 1)
