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
                    finite = false, max_level = "infinite"},
                  {id = "foreign-research", name = "Foreign research", family = "external",
                    finite = true, max_level = 3}
                }
              end
            }
          end

          package.preload["presentation.library_model"] = function()
            local function copy(row, technology, queue)
              return {
                id = row.id, name = row.name, family = row.family, finite = row.finite,
                max_level = row.max_level, cap = row.cap, cap_setting = row.cap_setting,
                current_level = technology and technology.level or 1,
                researched = technology and technology.researched or false,
                enabled = technology and technology.enabled or false,
                visible = technology and technology.visible_when_disabled or false,
                queued_count = queue and 1 or 0, prerequisites = {}
              }
            end
            return {
              normalize = function(view)
                return {
                  query = type(view.search) == "string" and view.search or (type(view.query) == "string" and view.query or ""),
                  family = view.family == "mir" and "mir" or "all",
                  selected = type(view.selected) == "string" and view.selected or nil
                }
              end,
              rows = function(force, rows, view, translations)
                assert(type(translations) == "table")
                local output = {}
                for _, row in ipairs(rows) do
                  local technology = force.technologies[row.id]
                  local name = string.lower(row.name)
                  local query = string.lower(view.query or view.search or "")
                  if (view.family == "all" or row.family == view.family)
                    and (query == "" or string.find(name, query, 1, true)) then
                    output[#output + 1] = copy(row, technology, false)
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
            local value = {valid = true, _parent = parent, _children = {}}
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
              prototype = {max_level = 4294967295}}
            foreign = {valid = true, name = "foreign-research", level = 1,
              researched = false, enabled = true, visible_when_disabled = false,
              prototype = {max_level = 3}}
            player = {valid = true, index = 1, gui = {screen = screen},
              force = {technologies = {[gear.name] = gear, [foreign.name] = foreign}}}
            player.set_shortcut_toggled = function(name, value)
              player.shortcut_name, player.shortcut_toggled = name, value
            end
            player.open_technology_gui = function(technology)
              player.opened_technology = technology
            end
            game = {get_player = function(index) return index == 1 and player or nil end}
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
          assert(next(storage) == nil and library.subscription_needs() == nil)
          library.on_lua_shortcut({prototype_name = "mir-research-browser", player_index = 1})
          local root = player.gui.screen["mir_research_browser"]
          assert(root and player.shortcut_name == "mir-research-browser" and player.shortcut_toggled)
          assert(storage.mir_library.schema == 1 and storage.mir_library.players[1].query == "")
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
          assert(cap_calls == 0 and library.subscription_needs() == nil)
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
          assert(detail["mir_library_detail_cap"].caption[2][1] == "mir-browser.setting-max-level")
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

    def test_configuration_migrates_published_browser_view_without_dropping_later_fidelity_fields(self):
        self.lua.execute(r'''
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
          assert(view.query == "historical gear" and view.family == "all")
          assert(view.selected == gear.name and view.scroll == 6)
          -- The currently open published frame location wins over its stale
          -- persisted location, as the old browser itself did on close.
          assert(view.location.x == 55 and view.location.y == 66)
          assert(storage.mir.research_browser.players[1] == historical)
          local preserved = state.legacy_browser
          assert(preserved.version == 1 and preserved.source == "storage.mir.research_browser")
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
          assert(view.query == "newer private query" and view.family == "mir")
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LibraryTests))
    sys.exit(0 if result.wasSuccessful() else 1)
