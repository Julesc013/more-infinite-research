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

          function startup_values(raw_cap, profile, worker_cap)
            return {
              ["ips-max-level-research_gears"] = {value = raw_cap},
              ["ips-enable-research_gears"] = {value = true},
              ["ips-cost-base-research_gears"] = {value = 8000},
              ["ips-cost-linear-increment-research_gears"] = {value = 0},
              ["ips-cost-growth-research_gears"] = {value = 2},
              ["ips-research-time-research_gears"] = {value = 60},
              ["ips-effect-per-level-research_gears"] = {value = 10},
              ["mir-max-level-worker-robots-speed"] = {value = worker_cap or 0},
              ["mir-settings-profile-import"] = {value = profile or ""}
            }
          end

          function boot(forces, raw_cap, profile, saved_storage, retained_handlers, worker_cap)
            storage = saved_storage or {}
            settings = {startup = startup_values(raw_cap, profile, worker_cap)}
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
            handlers = retained_handlers or {events = {}}
            handlers.events = handlers.events or {}
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
            package.loaded["runtime.bootstrap"] = nil
            package.loaded["runtime.library"] = nil
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
          package.loaded["runtime.bootstrap"] = nil
          package.loaded["runtime.library"] = nil
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
          local worker_probes = 0
          local f1_technologies = setmetatable({[name] = first}, {
            __index = function(value, key)
              if type(key) == "string" and key:find("worker-robots-speed", 1, true) then
                worker_probes = worker_probes + 1
                error("uncapped worker tail was probed")
              end
              return rawget(value, key)
            end
          })
          local f1 = force(1, f1_technologies, {first, first}, first, .42)
          local f2 = force(2, {[name] = second}, {}, nil, nil)
          first.force = f1
          boot({[1] = f1, [2] = f2}, 0, "{")
          assert(decoded_profiles == 1, "profile was not resolved during control parsing")
          handlers.init()
          handlers.events[defines.events.on_research_started]({research = first})
          handlers.events[defines.events.on_research_started]({research = first})
          assert(decoded_profiles == 1, "profile was decoded during a repeated research event")
          assert(worker_probes == 0, "uncapped worker tail was probed by gear events")
          assert(#f1.research_queue == 1 and f1.current_research == first and f1.research_progress == .42)
          assert(not second.enabled and second.visible_when_disabled and second.level == 11)
          assert(storage.mir_caps.schema == 1 and storage.mir_caps.owned_disabled[2][name].disabled)
          local saved_storage = storage
          local retained_handlers = handlers
          boot({[1] = f1, [2] = f2}, 0, "", saved_storage, retained_handlers)
          for id = 1, 6 do
            assert(handlers.events[id] == nil, "unlimited parse retained cap handler " .. id)
          end
          handlers.configuration()
          assert(second.enabled and not second.visible_when_disabled and storage.mir_caps == nil)
          handlers.init()
          assert(storage.mir_caps == nil, "unlimited callbacks allocated cap storage")
        ''')

    def test_research_events_remove_queued_current_and_reject_unresolved_current(self):
        self.lua.execute('''
          local name = "recipe-prod-research_gears-1"
          local gear = technology(name, 11, true)
          local unrelated_first = technology("unrelated-first", 1, true)
          local unrelated_second = technology("unrelated-second", 1, true)
          local f = force(4, {[name] = gear},
            {gear, unrelated_first, unrelated_second}, gear, .65)
          gear.force = f
          unrelated_first.force = f
          unrelated_second.force = f
          boot({[4] = f}, 10)
          handlers.events[defines.events.on_research_started]({research = gear})
          assert(f.cancelled == 0, "lifecycle used cancellation for a queued current research")
          assert(#f.research_queue == 2 and f.research_queue[1] == unrelated_first
            and f.research_queue[2] == unrelated_second, "unrelated queue order changed")
          assert(f.current_research == unrelated_first and f.research_progress == 0,
            "removed current research transferred progress")
          assert(not gear.enabled and gear.level == 11 and gear.researched == false)

          local unresolved = technology(name, 11, true)
          local unresolved_other = technology("unrelated-unresolved", 1, true)
          local f_unresolved = force(5, {[name] = unresolved}, {unresolved_other}, unresolved, .75)
          unresolved.force = f_unresolved
          unresolved_other.force = f_unresolved
          local ok, message = pcall(handlers.events[defines.events.on_research_started],
            {research = unresolved})
          assert(not ok and tostring(message):find("unsupported native research queue state", 1, true))
          assert(f_unresolved.cancelled == 0 and f_unresolved.current_research == unresolved
            and f_unresolved.research_progress == .75 and #f_unresolved.research_queue == 1
            and f_unresolved.research_queue[1] == unresolved_other,
            "unresolved current research was speculatively cancelled or rewritten")
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

    def test_admitted_native_worker_tail_cap_is_per_force_and_restores_owned_state(self):
        self.lua.execute('''
          local owner = "worker-robots-speed-6"
          local predecessor = "worker-robots-speed-5"
          local function native_tail(level, enabled, effects)
            local value = technology(owner, level, enabled)
            value.prototype = {
              max_level = 4294967295,
              effects = effects or {{type = "worker-robot-speed", modifier = .65}}
            }
            value.prerequisites = {[predecessor] = {name = predecessor}}
            return value
          end
          local admitted = native_tail(11, true)
          local f = force(12, {[owner] = admitted}, {}, nil, nil)
          admitted.force = f
          boot({[12] = f}, 0, "", nil, nil, 10)
          local lifecycle = require("runtime.lifecycle")
          assert(lifecycle.caps_active())
          local limits = lifecycle.cap_limits(f)
          assert(limits[owner] == 10 and limits["recipe-prod-research_gears-1"] == 0)
          limits[owner] = 99
          assert(lifecycle.cap_limits(f)[owner] == 10, "cap snapshot was shared")
          handlers.init()
          assert(not admitted.enabled and admitted.visible_when_disabled and admitted.level == 11)
          assert(storage.mir_caps.owned_disabled[12][owner].disabled)

          local saved_storage = storage
          boot({[12] = f}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          assert(admitted.enabled and not admitted.visible_when_disabled and storage.mir_caps == nil,
            "unlimited native cap did not restore MIR-owned state")
          assert(require("runtime.lifecycle").cap_limits(f)[owner] == 0,
            "Library snapshot did not expose the unlimited native cap")

          local foreign = native_tail(11, false)
          local foreign_force = force(13, {[owner] = foreign}, {}, nil, nil)
          foreign.force = foreign_force
          boot({[13] = foreign_force}, 0, "", nil, nil, 10)
          handlers.init()
          assert(not foreign.enabled and foreign.visible_when_disabled)
          assert(storage.mir_caps.owned_disabled[13][owner].disabled == nil)
          saved_storage = storage
          boot({[13] = foreign_force}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          assert(not foreign.enabled and not foreign.visible_when_disabled,
            "native relaxation changed foreign enablement")

          local malformed = native_tail(11, true, {
            {type = "worker-robot-speed", modifier = .65},
            {type = "laboratory-speed", modifier = .1}
          })
          local malformed_force = force(14, {[owner] = malformed}, {}, nil, nil)
          malformed.force = malformed_force
          boot({[14] = malformed_force}, 0, "", nil, nil, 10)
          local malformed_limits = require("runtime.lifecycle").cap_limits(malformed_force)
          assert(malformed_limits[owner] == nil)
          handlers.init()
          assert(malformed.enabled and not malformed.visible_when_disabled and storage.mir_caps == nil,
            "malformed native tail was managed")
        ''')

    def test_worker_tail_binding_change_discards_stale_enablement_right(self):
        self.lua.execute('''
          local six = "worker-robots-speed-6"
          local seven = "worker-robots-speed-7"
          local function tail(name, predecessor, level, enabled, effects)
            local value = technology(name, level, enabled)
            value.prototype = {
              max_level = 4294967295,
              effects = effects or {{type = "worker-robot-speed", modifier = .65}}
            }
            value.prerequisites = {[predecessor] = {name = predecessor}}
            return value
          end
          local old_six = tail(six, "worker-robots-speed-5", 11, true)
          local f = force(15, {[six] = old_six}, {}, nil, nil)
          old_six.force = f
          boot({[15] = f}, 0, "", nil, nil, 10)
          handlers.init()
          assert(not old_six.enabled and storage.mir_caps.owned_disabled[15][six].disabled)

          old_six.prototype.effects = {
            {type = "worker-robot-speed", modifier = .65},
            {type = "laboratory-speed", modifier = .1}
          }
          local raw_technologies, tail_reads = f.technologies, 0
          f.technologies = setmetatable({}, {__index = function(_, name)
            if name == six or name == seven then tail_reads = tail_reads + 1 end
            return raw_technologies[name]
          end})
          handlers.configuration()
          assert(tail_reads == 2, "malformed tail selection examined more than two candidates")
          assert(storage.mir_caps == nil and not old_six.enabled and old_six.visible_when_disabled,
            "malformed upstream tail retained an enablement right or was re-enabled")

          local new_seven = tail(seven, six, 1, true)
          f.technologies[seven] = new_seven
          handlers.configuration()
          local limits = require("runtime.lifecycle").cap_limits(f)
          assert(limits[six] == nil and limits[seven] == 10,
            "higher-priority admitted tail did not replace the malformed binding")

          local saved_storage = storage
          boot({[15] = f}, 0, "", saved_storage, nil, 0)
          handlers.configuration()
          local foreign_replacement = tail(six, "worker-robots-speed-5", 11, false)
          f.technologies[six] = foreign_replacement
          handlers.configuration()
          assert(not foreign_replacement.enabled and not foreign_replacement.visible_when_disabled
              and storage.mir_caps == nil,
            "stale worker-six cap ownership re-enabled a foreign replacement")
        ''')

    def test_lifecycle_source_has_no_tick_or_runtime_generator_import(self):
        source = (ROOT / "source/mir5/runtime/lifecycle.lua").read_text()
        control = (ROOT / "source/mir5/control.lua").read_text(encoding="utf-8")
        bootstrap = (ROOT / "source/mir5/runtime/bootstrap.lua").read_text(encoding="utf-8")
        self.assertNotIn("on_tick", source)
        self.assertNotIn("generator", source.lower())
        self.assertNotIn("cancel_current_research", source)
        self.assertNotIn("documented exception", source)
        self.assertNotIn("require(", source[source.index("function M.on_init"):])
        self.assertIn('require("runtime.bootstrap")', control)
        self.assertIn("function M.register()", bootstrap)
        self.assertIn("remote.add_interface", bootstrap)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LifecycleTests))
    sys.exit(0 if result.wasSuccessful() else 1)
