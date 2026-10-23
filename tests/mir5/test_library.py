"""Pure Lua 5.2 controls for the private MIR5 Library slice, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LibraryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
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

          function gui_container(parent)
            local value = {valid = true, parent = parent, _parent = parent, _children = {}}
            value.add = function(spec)
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
              return element
            end
            return value
          end

          function boot()
            storage = {}
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
        ''')

    def test_pure_prototype_constructor_preserves_published_shortcut_identity(self):
        self.lua.globals().prototype_source = (ROOT / "source/mir5/presentation/shortcut.lua").as_posix()
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
          local rows = root["mir_library_content"]["mir_library_results"]
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
          library.on_gui_click({player_index = 1, element = root["mir_library_content"]["mir_library_actions"]["mir_library_open_native"]})
          assert(player.opened_technology == gear and player.gui.screen["mir_research_browser"] == nil)
          assert(not player.shortcut_toggled)
          library.open(player)
          root = player.gui.screen["mir_research_browser"]
          assert(root.location.x == 91 and root.location.y == 44)
          assert(root["mir_library_content"]["mir_library_results"].scrolled_to.index == 1)
          library.on_gui_click({player_index = 1, element = root["mir_library_content"]["mir_library_actions"]["mir_library_close"]})
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
          assert(#root["mir_library_content"]["mir_library_results"].items == 1)
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
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Gear translated")
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
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Iron gear wheel productivity")
          assert(library.subscription_needs() == false)
          library.on_player_locale_changed({player_index = 1})
          assert(#player.translation_requests == 2)

          local locale_current = player.translation_requests[2].id
          player.force.index = 2
          library.on_string_translated({player_index = 1, id = locale_current,
            translated = true, result = "incorrect force label"})
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Iron gear wheel productivity")
          library.on_player_changed_force({player_index = 1})
          assert(#player.translation_requests == 3)

          local current = player.translation_requests[3].id
          root = player.gui.screen["mir_research_browser"]
          root.destroy()
          library.on_string_translated({player_index = 1, id = current,
            translated = true, result = "rootless label"})
          assert(player.gui.screen["mir_research_browser"] == nil and library.subscription_needs() == false)
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
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Iron gear wheel productivity")

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
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Iron gear wheel productivity")
          library.on_string_translated({player_index = 1, id = force_gear,
            translated = true, result = "Zahnrad"})
          library.on_string_translated({player_index = 1, id = force_foreign,
            translated = true, result = "Fremde Forschung"})
          root = player.gui.screen["mir_research_browser"]
          assert(root["mir_library_content"]["mir_library_results"].items[1] == "Zahnrad")

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
          local rows = root["mir_library_content"]["mir_library_results"]
          assert(#rows.items == 1 and rows.items[1] == "Iron gear wheel productivity")
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})

          root = player.gui.screen["mir_research_browser"]
          local detail = root["mir_library_content"]["mir_library_detail"]
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
          local detail = root["mir_library_content"]["mir_library_detail"]
          assert(cap_calls == 1 and detail["mir_library_detail_cap"] == nil)
          local rows = root["mir_library_content"]["mir_library_results"]
          rows.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = rows})
          root = player.gui.screen["mir_research_browser"]
          detail = root["mir_library_content"]["mir_library_detail"]
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
          boot()
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          local query = root["mir_library_filters"]["mir_library_query"]
          query.text = "research_gears"
          library.on_gui_text_changed({player_index = 1, element = query})
          root = player.gui.screen["mir_research_browser"]
          local results = root["mir_library_content"]["mir_library_results"]
          assert(#results.items == 1 and results.items[1] == "recipe-prod-research_gears-1")
          results.selected_index = 1
          library.on_gui_selection_state_changed({player_index = 1, element = results})
          assert(storage.mir_library.players[1].selected == gear.name)
          assert(player.gui.screen["mir_research_browser"]["mir_library_content"]["mir_library_detail"] ~= nil)
        ''')

    def test_level_modes_filter_real_native_rows_and_preserve_owned_personal_state(self):
        self.lua.execute('''
          package.preload["research.catalogue"], package.preload["presentation.library_model"] = nil, nil
          package.loaded["research.catalogue"], package.loaded["presentation.library_model"] = nil, nil
          boot()
          local native_queue, native_current = player.force.research_queue, player.force.current_research
          library.open(player, {family = "all", mode = 2, page = 7})
          local view = storage.mir_library.players[1]
          local root = player.gui.screen["mir_research_browser"]
          local filters, content = root["mir_library_filters"], root["mir_library_content"]
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
          assert(#root["mir_library_content"]["mir_library_results"].items == 2)
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
          local rows = root["mir_library_content"]["mir_library_results"]
          assert(#rows.items == 2 and rows.items[1] == gear.name and rows.items[2] == foreign.name)

          -- The historical page value survives reopening, but it was never a
          -- player-list paginator: the continuous list retains both rows.
          library.close(player)
          library.open(player)
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = root["mir_library_content"]["mir_library_results"]
          assert(view.page == 7 and #rows.items == 2
            and rows.items[1] == gear.name and rows.items[2] == foreign.name)

          -- The valid dense remote list changes actual rendering and an
          -- explicit valid page wins over the normal filter page reset.
          library.open(player, {hidden = {foreign.name}, page = 7})
          view = storage.mir_library.players[1]
          root = player.gui.screen["mir_research_browser"]
          rows = root["mir_library_content"]["mir_library_results"]
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
          local filters, content = root["mir_library_filters"], root["mir_library_content"]
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
          filters, content = root["mir_library_filters"], root["mir_library_content"]
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
          for _, invalid in ipairs({0, 3, 1.5, "2", 0/0}) do
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
          assert(view.visibility == 2 and view.page == 7, "invalid owned visibility was accepted")
          family.selected_index = 7
          library.on_gui_selection_state_changed({player_index = 1, element = family})
          view = storage.mir_library.players[1]
          assert(view.family == "external" and view.page == 7, "invalid owned family was accepted")

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
          storage.mir = {research_browser = {players = {[1] = historical}}}
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
          -- The currently open published frame location wins over its stale
          -- persisted location, as the old browser itself did on close.
          assert(view.location.x == 55 and view.location.y == 66)
          assert(storage.mir.research_browser.players[1] == historical)
          local preserved = state.legacy_browser
          assert(preserved.version == 1 and preserved.source == "storage.mir.research_browser")
          assert(preserved.authoritative_source == "storage.mir.research_browser")
          assert(preserved.snapshot_status[1].complete and not preserved.snapshot_status[1].truncated)
          local saved = preserved.players[1]
          assert(saved.mode == 3 and saved.status == 2 and saved.page == 7)
          assert(saved.tab == "settings" and saved.settings_scope == "options")
          assert(saved.sort == "name-asc" and saved.stable_sort == "native")
          assert(saved.settings_search == "cost tuning" and saved.visibility == 2)
          assert(saved.hidden["foreign-research"] and saved.geometry.width == 900)
          assert(saved.report_settings == false and saved.report_omissions == true)
          assert(old.valid == false)
          local root = player.gui.screen["mir_research_browser"]
          assert(root and root ~= old and root["mir_library_filters"] and root["mir_library_content"])
          assert(player.shortcut_toggled == true)
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
        source = (ROOT / "source/mir5/runtime/library.lua").read_text()
        self.assertNotIn("script.on_event", source)
        self.assertNotIn("script.on_nth_tick", source)
        self.assertNotIn("remote.add_interface", source)
        self.assertNotIn("prototypes.mir", source)
        self.assertNotIn("force.caps", source)
        self.assertNotIn("game.create_player", source)
        self.assertNotIn("force.research_queue =", source)
        self.assertNotIn("force.add_research", source)
        self.assertNotIn("force.cancel_current_research", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryTests))
    sys.exit(0 if result.wasSuccessful() else 1)
