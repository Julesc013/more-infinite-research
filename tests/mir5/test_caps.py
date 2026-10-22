"""Pure Lua 5.2 controls for MIR 5 absolute-cap reconciliation, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CapsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          caps = require("runtime.caps")

          function technology(name, level, enabled)
            return {name = name, level = level, enabled = enabled ~= false,
              researched = false, visible_when_disabled = false}
          end

          function force(index, technologies, queue, current, progress)
            local value = {valid = true, index = index, technologies = technologies,
              _queue = queue, current_research = current, research_progress = progress,
              worker_robots_speed_modifier = 7.15}
            return setmetatable(value, {
              __index = function(self, key)
                if key == "research_queue" then return rawget(self, "_queue") end
                return rawget(self, key)
              end,
              __newindex = function(self, key, replacement)
                if key ~= "research_queue" then rawset(self, key, replacement); return end
                rawset(self, "_queue", replacement)
                local current = rawget(self, "current_research")
                local retained = false
                for _, item in ipairs(replacement) do
                  if item == current then retained = true; break end
                end
                if not retained then
                  rawset(self, "current_research", replacement[1])
                  rawset(self, "research_progress", replacement[1] and 0 or nil)
                end
              end
            })
          end
        ''')

    def test_cap_ten_keeps_level_ten_and_removes_level_eleven_queue_entry(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 10, true)
          local f = force(1, {[speed.name] = speed}, {speed, speed}, speed, .42)
          local ownership, result = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(result.queue_changed and #f.research_queue == 1 and f.research_queue[1] == speed)
          assert(result.removed_current == nil and result.unresolved_current == nil)
          assert(f.current_research == speed and f.research_progress == .42)
          assert(speed.enabled and ownership[1] == nil)
        ''')

    def test_earned_above_cap_disables_without_changing_earned_state(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 11, true)
          speed.researched = true
          local f = force(2, {[speed.name] = speed}, {}, nil, nil)
          local ownership = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(not speed.enabled and speed.level == 11 and speed.researched)
          assert(speed.visible_when_disabled and f.worker_robots_speed_modifier == 7.15)
          assert(ownership[2][speed.name].disabled and ownership[2][speed.name].visible_when_disabled == false)
        ''')

    def test_foreign_disabled_technology_stays_disabled_when_uncapped(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 11, false)
          local f = force(3, {[speed.name] = speed}, {}, nil, nil)
          local ownership = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(not speed.enabled and speed.visible_when_disabled)
          assert(ownership[3][speed.name].disabled == nil
            and ownership[3][speed.name].visible_when_disabled == false)
          caps.reconcile(f, {[speed.name] = 0}, ownership)
          assert(not speed.enabled and not speed.visible_when_disabled and ownership[3] == nil)
        ''')

    def test_queue_filter_preserves_order_and_unrelated_current_progress(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 10, true)
          local first = technology("unrelated-first", 1, true)
          local second = technology("unrelated-second", 1, true)
          local f = force(4, {[speed.name] = speed, [first.name] = first, [second.name] = second},
            {first, speed, second, speed, speed}, first, .25)
          local _, result = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(result.queue_changed and #f.research_queue == 3)
          assert(f.research_queue[1] == first and f.research_queue[2] == speed
            and f.research_queue[3] == second)
          assert(f.current_research == first and f.research_progress == .25)
          assert(speed.enabled)
        ''')

    def test_over_cap_current_is_removed_without_transferring_its_progress(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 11, true)
          local f = force(5, {[speed.name] = speed}, {speed}, speed, .8)
          local _, result = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(result.queue_changed and result.removed_current == speed.name
            and result.unresolved_current == nil)
          assert(#f.research_queue == 0 and f.current_research == nil and f.research_progress == nil)
        ''')

    def test_unqueued_over_cap_current_is_reported_without_guessing_a_native_write(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 11, true)
          local unrelated = technology("unrelated", 1, true)
          local f = force(7, {[speed.name] = speed, [unrelated.name] = unrelated},
            {unrelated}, speed, .5)
          local _, result = caps.reconcile(f, {[speed.name] = 10}, {})
          assert(not result.queue_changed and result.unresolved_current == speed.name)
          assert(f.current_research == speed and f.research_progress == .5)
        ''')

    def test_uncap_restoration_is_owned_and_idempotent(self):
        self.lua.execute('''
          local speed = technology("worker-robots-speed-6", 11, true)
          local f = force(6, {[speed.name] = speed}, {}, nil, nil)
          local ownership = {}
          ownership = caps.reconcile(f, {[speed.name] = 10}, ownership)
          assert(not speed.enabled and speed.visible_when_disabled and ownership[6][speed.name].disabled)
          ownership = caps.reconcile(f, {[speed.name] = 0}, ownership)
          assert(speed.enabled and not speed.visible_when_disabled and ownership[6] == nil)
          caps.reconcile(f, {[speed.name] = 0}, ownership)
          assert(speed.enabled and ownership[6] == nil)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CapsTests))
    sys.exit(0 if result.wasSuccessful() else 1)
