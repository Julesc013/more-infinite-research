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

          function install_modules(caps_enabled)
            CAP_ACTIVE = caps_enabled == true
            lifecycle_calls = {}
            library_calls = {}
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
                on_research_started = function(event) lifecycle_calls.research_started = event end,
                on_research_cancelled = function(event) lifecycle_calls.research_cancelled = event end
              }
            end
            package.preload["runtime.library"] = function()
              local module = {}
              module.set_cap_provider = function(provider) library_calls.provider = provider end
              module.open = function(player, options)
                library_calls.open = {player = player, options = options}
                return player.frame
              end
              module.on_init = function() library_calls.init = (library_calls.init or 0) + 1 end
              module.on_configuration_changed = function(event) library_calls.configuration = event end
              module.on_load = function() library_calls.load = (library_calls.load or 0) + 1 end
              module.on_lua_shortcut = function(event) library_calls.shortcut = event end
              module.on_gui_text_changed = function(event) library_calls.text = event end
              module.on_gui_selection_state_changed = function(event) library_calls.selection = event end
              module.on_gui_click = function(event) library_calls.click = event end
              module.on_gui_location_changed = function(event) library_calls.location = event end
              module.on_gui_closed = function(event) library_calls.closed = event end
              module.on_player_removed = function(event) library_calls.removed = event end
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

          function install_runtime(foreign_interfaces)
            handlers = {events = {}}
            remote = {interfaces = foreign_interfaces or {}}
            remote.add_interface = function(name, members)
              remote.interfaces[name] = members
            end
            commands = {registered = {}}
            commands.add_command = function(name, help, callback)
              commands.registered[name] = {help = help, callback = callback}
            end
            script = {
              on_init = function(callback) handlers.init = callback end,
              on_configuration_changed = function(callback) handlers.configuration = callback end,
              on_load = function(callback) handlers.load = callback end,
              on_event = function(id, callback) handlers.events[id] = callback end
            }
            defines = {events = {
              on_force_created = 1, on_force_reset = 2, on_forces_merged = 3,
              on_research_finished = 4, on_research_started = 5, on_research_cancelled = 6,
              on_lua_shortcut = 7, on_gui_text_changed = 8,
              on_gui_selection_state_changed = 9, on_gui_click = 10,
              on_gui_location_changed = 11, on_gui_closed = 12, on_player_removed = 13
            }}
            known_technology = {valid = true, name = "recipe-prod-research_gears-1"}
            player = {valid = true, index = 1, frame = {valid = true},
              force = {technologies = {[known_technology.name] = known_technology}}}
            game = {get_player = function(index) return index == 1 and player or nil end}
          end

          function load_control()
            package.loaded["control"] = nil
            package.loaded["runtime.bootstrap"] = nil
            package.loaded["runtime.lifecycle"] = nil
            package.loaded["runtime.library"] = nil
            package.loaded["api.v1.runtime"] = nil
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
          assert(commands.registered["mir-research"].help[1] == "mir-browser.command")

          assert(type(handlers.init) == "function" and type(handlers.configuration) == "function"
            and type(handlers.load) == "function")
          handlers.init(); handlers.configuration({mod_changes = {}}); handlers.load()
          assert(lifecycle_calls.init == 1 and library_calls.init == 1)
          assert(lifecycle_calls.configuration.mod_changes and library_calls.configuration.mod_changes)
          assert(lifecycle_calls.load == 1 and library_calls.load == 1)

          for id = 1, 6 do assert(type(handlers.events[id]) == "function") end
          assert(handlers.events[1] == nil or handlers.events[1] ~= handlers.events[7])
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
          handlers.events[7]({player_index = 1})
          handlers.events[8]({player_index = 1})
          handlers.events[9]({player_index = 1})
          handlers.events[10]({player_index = 1})
          handlers.events[11]({player_index = 1})
          handlers.events[12]({player_index = 1})
          handlers.events[13]({player_index = 1})
          assert(library_calls.shortcut.player_index == 1 and library_calls.text.player_index == 1)
          assert(library_calls.selection.player_index == 1 and library_calls.click.player_index == 1)
          assert(library_calls.location.player_index == 1 and library_calls.closed.player_index == 1
            and library_calls.removed.player_index == 1)

          local cap_map = library_calls.provider(player.force)
          assert(cap_map[known_technology.name] == 2 and lifecycle_calls.cap_force == player.force)
          assert(browser.open(77, {}) == false and library_calls.open == nil)
          assert(browser.open(1, {search = "gear", family = "mir", selected = known_technology.name}))
          assert(library_calls.open.player == player and library_calls.open.options.query == "gear")
          assert(library_calls.open.options.family == "mir"
            and library_calls.open.options.selected == known_technology.name)
          assert(browser.open(1, {selected = "unknown", family = "external"}))
          assert(library_calls.open.options.family == nil and library_calls.open.options.selected == nil)
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
          for id = 7, 13 do assert(type(handlers.events[id]) == "function") end
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

    def test_bootstrap_has_no_late_module_loading_or_periodic_dispatch(self):
        source = (ROOT / "source/mir5/runtime/bootstrap.lua").read_text(encoding="utf-8")
        control = (ROOT / "source/mir5/control.lua").read_text(encoding="utf-8")
        self.assertNotIn("on_tick", source)
        self.assertNotIn("on_nth_tick", source)
        self.assertNotIn("require(", source[source.index("function M.register"):])
        self.assertIn('require("runtime.bootstrap")', control)
        self.assertIn("remote.add_interface", control)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BootstrapTests))
    sys.exit(0 if result.wasSuccessful() else 1)
