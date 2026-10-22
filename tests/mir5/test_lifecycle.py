"""Pure Lua 5.2 controls for MIR 5 lifecycle wiring, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""

          function technology(name, level, enabled)
            return {name = name, level = level, researched = false,
              enabled = enabled ~= false, visible_when_disabled = false}
          end

          function force(index, technologies, queue, current, progress)
            local value = {valid = true, index = index, technologies = technologies,
              _queue = queue or {}, current_research = current, research_progress = progress,
              cancelled = 0}
            value.cancel_current_research = function()
              value.cancelled = value.cancelled + 1
              value.current_research = nil
              value.research_progress = nil
              value._queue = {}
            end
            return setmetatable(value, {
              __index = function(self, key)
                if key == "research_queue" then return rawget(self, "_queue") end
                return rawget(self, key)
              end,
              __newindex = function(self, key, replacement)
                if key ~= "research_queue" then rawset(self, key, replacement); return end
                rawset(self, "_queue", replacement)
                local current_research = rawget(self, "current_research")
                local retained = false
                for _, item in ipairs(replacement) do
                  if item == current_research then retained = true; break end
                end
                if not retained then
                  rawset(self, "current_research", replacement[1])
                  rawset(self, "research_progress", replacement[1] and 0 or nil)
                end
              end
            })
          end

          function startup_values(raw_cap, profile)
            return {
              ["ips-max-level-research_gears"] = {value = raw_cap},
              ["ips-enable-research_gears"] = {value = true},
              ["ips-cost-base-research_gears"] = {value = 8000},
              ["ips-cost-linear-increment-research_gears"] = {value = 0},
              ["ips-cost-growth-research_gears"] = {value = 2},
              ["ips-research-time-research_gears"] = {value = 60},
              ["ips-effect-per-level-research_gears"] = {value = 10},
              ["mir-settings-profile-import"] = {value = profile or ""}
            }
          end

          function boot(forces, raw_cap, profile, saved_storage)
            storage = saved_storage or {}
            settings = {startup = startup_values(raw_cap, profile)}
            decoded_profiles = 0
            helpers = {
              json_to_table = function(_) decoded_profiles = decoded_profiles + 1
                return {schema = 1, kind = "mir-settings-profile", settings = {
                  ["ips-max-level-research_gears"] = 10
                }}
              end,
              decode_string = function(value) return value end,
              encode_string = function(value) return value end
            }
            logs = {}
            log = function(message) logs[#logs + 1] = message end
            game = {forces = forces}
            handlers = {events = {}}
            script = {
              on_init = function(handler) handlers.init = handler end,
              on_configuration_changed = function(handler) handlers.configuration = handler end,
              on_load = function(handler) handlers.load = handler end,
              on_event = function(id, handler) handlers.events[id] = handler end
            }
            defines = {events = {
              on_force_created = 1, on_force_reset = 2, on_forces_merged = 3,
              on_research_finished = 4, on_research_started = 5, on_research_cancelled = 6
            }}
            remote = {interfaces = {}, removed = false}
            remote.add_interface = function(name, functions) remote.interfaces[name] = functions end
            remote.remove_interface = function(_) remote.removed = true end
            package.loaded["control"] = nil
            package.loaded["runtime.lifecycle"] = nil
            control = require("control")
          end
        ''')

    def test_unlimited_control_registers_no_cap_handlers_or_storage(self):
        self.lua.execute('''
          boot({}, 0)
          local api = remote.interfaces["more-infinite-research.api.v1"]
          assert(type(api) == "table" and type(api.get_version) == "function"
            and type(api.get_capabilities) == "function" and type(api.get_research) == "function")
          assert(type(handlers.init) == "function" and type(handlers.configuration) == "function"
            and type(handlers.load) == "function")
          for id = 1, 6 do assert(handlers.events[id] == nil) end
          assert(handlers.events[7] == nil and remote.removed == false and next(storage) == nil)
          handlers.init(); handlers.configuration()
          assert(next(storage) == nil, "unlimited settings allocated cap storage")
          local before = next(storage)
          handlers.load()
          assert(before == next(storage), "on_load initialized or changed storage")
        ''')

    def test_foreign_interface_collision_fails_without_removing_it(self):
        self.lua.execute('''
          storage = {}; settings = {startup = startup_values(0, "")}
          helpers = {}; game = {forces = {}}
          script = {on_init = function() end, on_configuration_changed = function() end,
            on_load = function() end, on_event = function() end}
          defines = {events = {}}
          local foreign = {}
          remote = {interfaces = {["more-infinite-research.api.v1"] = foreign}, removed = false}
          remote.add_interface = function() error("unexpected replacement") end
          remote.remove_interface = function() remote.removed = true end
          package.loaded["control"] = nil
          package.loaded["runtime.lifecycle"] = nil
          local ok, message = pcall(require, "control")
          assert(not ok and tostring(message):find("MIR API interface collision", 1, true))
          assert(remote.interfaces["more-infinite-research.api.v1"] == foreign and not remote.removed)
        ''')

    def test_profile_cap_is_resolved_once_and_preserves_valid_current_progress(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local first = technology(name, 10, true)
          local second = technology(name, 11, true)
          local f1 = force(1, {[name] = first}, {first, first}, first, .42)
          local f2 = force(2, {[name] = second}, {}, nil, nil)
          first.force = f1
          boot({[1] = f1, [2] = f2}, 0, "{")
          assert(decoded_profiles == 1, "profile was not resolved during control parsing")
          handlers.init()
          handlers.events[defines.events.on_research_started]({research = first})
          handlers.events[defines.events.on_research_started]({research = first})
          assert(decoded_profiles == 1, "profile was decoded during a repeated research event")
          assert(#f1.research_queue == 1 and f1.current_research == first and f1.research_progress == .42)
          assert(not second.enabled and second.visible_when_disabled and second.level == 11)
          assert(storage.mir_caps.schema == 1 and storage.mir_caps.owned_disabled[2][name].disabled)
          local saved_storage = storage
          boot({[1] = f1, [2] = f2}, 0, "", saved_storage)
          assert(handlers.events[defines.events.on_research_started] == nil)
          handlers.configuration()
          assert(second.enabled and not second.visible_when_disabled and storage.mir_caps == nil)
        ''')

    def test_research_events_cancel_only_an_unqueued_admitted_overcap_current(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local gear = technology(name, 11, true)
          local f = force(4, {[name] = gear}, {}, gear, .65)
          gear.force = f
          boot({[4] = f}, 10)
          handlers.events[defines.events.on_research_started]({research = gear})
          assert(f.cancelled == 1 and f.current_research == nil and f.research_progress == nil)
          assert(not gear.enabled and gear.level == 11 and gear.researched == false)
          f.current_research = gear; f.research_progress = .55
          handlers.events[defines.events.on_research_finished]({research = gear})
          assert(f.cancelled == 2 and f.current_research == nil and f.research_progress == nil)
          f.current_research = gear; f.research_progress = .75
          handlers.events[defines.events.on_research_cancelled]({force = f, research = {[name] = 1}})
          assert(f.cancelled == 3 and f.current_research == nil and f.research_progress == nil)
          local unrelated = technology("unrelated", 11, true)
          unrelated.force = f
          f.current_research = unrelated; f.research_progress = .3
          handlers.events[defines.events.on_research_started]({research = unrelated})
          assert(f.cancelled == 3 and f.current_research == unrelated and f.research_progress == .3)
        ''')

    def test_foreign_disable_and_force_lifecycle_cleanup_remain_owned(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local foreign = technology(name, 11, false)
          local source = force(7, {[name] = foreign}, {}, nil, nil)
          local destination = force(8, {[name] = technology(name, 10, true)}, {}, nil, nil)
          boot({[7] = source, [8] = destination}, 10)
          handlers.init()
          assert(not foreign.enabled and foreign.visible_when_disabled, "cap did not preserve foreign disablement")
          assert(storage.mir_caps.owned_disabled[7][name].disabled == nil,
            "unexpected foreign disable ownership: " .. tostring(storage.mir_caps.owned_disabled[7][name].disabled))
          local saved_storage = storage
          boot({[7] = source, [8] = destination}, 0, "", saved_storage)
          handlers.configuration()
          assert(not foreign.enabled and not foreign.visible_when_disabled, "uncap changed foreign enablement or visibility")
          saved_storage = storage
          boot({[7] = source, [8] = destination}, 10, "", saved_storage)
          handlers.configuration()
          storage.mir_caps.owned_disabled[8] = {stale = {disabled = true}}
          handlers.events[defines.events.on_force_created]({force = destination})
          assert(storage.mir_caps.owned_disabled[8] == nil, "force creation retained stale ownership")
          storage.mir_caps.owned_disabled[8] = {stale = {disabled = true}}
          handlers.events[defines.events.on_force_reset]({force = destination})
          assert(storage.mir_caps.owned_disabled[8] == nil, "force reset retained stale ownership")
          storage.mir_caps.owned_disabled[7].stale = {disabled = true}
          source.valid = false
          handlers.events[defines.events.on_forces_merged]({source_index = 7, destination = destination})
          assert(storage.mir_caps == nil, "merged source retained ownership")
          saved_storage = storage
          boot({[7] = source, [8] = destination}, 0, "", saved_storage)
          handlers.configuration()
          assert(storage.mir_caps == nil, "uncap retained empty ownership state")
        ''')

    def test_lifecycle_source_has_no_tick_or_runtime_generator_import(self):
        source = (ROOT / "source/mir5/runtime/lifecycle.lua").read_text()
        control = (ROOT / "source/mir5/control.lua").read_text()
        self.assertNotIn("on_tick", source)
        self.assertNotIn("generator", source.lower())
        self.assertNotIn("require(", source[source.index("function M.on_init"):])
        self.assertIn('remote.add_interface', control)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LifecycleTests))
    sys.exit(0 if result.wasSuccessful() else 1)
