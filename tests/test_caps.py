"""Pure Lua 5.2 controls for MIR 5 absolute-cap reconciliation, not native evidence."""
import argparse
from pathlib import Path
import sys
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CapsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
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
          assert(ownership[3][speed.name].disabled == false
            and ownership[3][speed.name].visible_when_disabled == false)
          caps.reconcile(f, {[speed.name] = 0}, ownership)
          assert(not speed.enabled and not speed.visible_when_disabled and ownership[3] == nil)
        ''')

    def test_native_reenable_during_finite_cap_never_acquires_foreign_restoration_right(self):
        self.lua.globals().old_caps_source = subprocess.check_output([
            "git", "show", "c37fca88667d550660f5b9c0efd7f272b56d6025:source/runtime/caps.lua"
        ], cwd=ROOT).decode("utf-8")
        self.lua.execute('''
          local old = assert(load(old_caps_source, "published-e3-caps", "t", _G))()
          for _, visible in ipairs({false, true}) do
            for _, module in ipairs({caps, old}) do
              local owner = technology("steel-plate-productivity", 2, false)
              owner.visible_when_disabled = visible
              local unrelated = technology("automation", 1, true)
              local f = force(22, {[owner.name]=owner,[unrelated.name]=unrelated}, {unrelated}, unrelated, .42)
              local rows = {}
              module.reconcile(f, {[owner.name]=1}, rows)
              -- The engine exposes enabled=true again across a prototype
              -- configuration/reset, while the same finite cap still applies.
              owner.enabled = true
              module.reconcile(f, {[owner.name]=1}, rows)
              assert(not owner.enabled and owner.level == 2 and not owner.researched)
              module.reconcile(f, {[owner.name]=0}, rows)
              assert(owner.enabled == (module == old), "foreign baseline was promoted into a restoration right")
              assert(owner.visible_when_disabled == visible)
              assert(f.current_research == unrelated and f.research_progress == .42 and #f.research_queue == 1)
              assert(rows[22] == nil)
            end
          end
        ''')

    def test_legacy_visibility_only_row_preserves_its_foreign_baseline(self):
        self.lua.execute('''
          local owner = technology("steel-plate-productivity", 2, true)
          owner.visible_when_disabled = true
          local f = force(23, {[owner.name]=owner}, {}, nil, nil)
          local rows = {[23]={[owner.name]={visible_when_disabled=false}}}
          caps.reconcile(f, {[owner.name]=1}, rows)
          assert(rows[23][owner.name].disabled == false and not owner.enabled)
          caps.reconcile(f, {[owner.name]=0}, rows)
          assert(not owner.enabled and not owner.visible_when_disabled and rows[23] == nil)
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

    def test_first_import_proof_is_bound_to_the_written_record_and_live_state(self):
        self.lua.execute('''
          local function check(kind, expected)
            local item = technology("recipe-prod-research_gears-1", 3, kind ~= "already-disabled")
            local row = {visible_when_disabled = false}
            if kind == "current-negative" then row.disabled = false end
            local ownership = {[1] = {[item.name] = row}}
            local proof = kind == "stale-record" and {visible_when_disabled = false} or row
            local f = force(1, {[item.name] = item}, {}, nil, nil)
            caps.reconcile(f, {[item.name] = 2}, ownership, nil, {[item.name] = proof})
            assert(not item.enabled and ownership[1][item.name].disabled == expected,
              kind .. " did not preserve the exact new-write ownership boundary")
            caps.reconcile(f, {[item.name] = 0}, ownership)
            assert(item.enabled == expected and not item.visible_when_disabled and ownership[1] == nil)
          end
          check("newly-imported", true)
          check("stale-record", false)
          check("current-negative", false)
          check("already-disabled", false)
          local item = technology("recipe-prod-research_gears-1", 3, true)
          local row = {visible_when_disabled = false}
          local owned = {[1] = {[item.name] = row}}
          caps.reconcile(force(1, {[item.name] = item}, {}, nil, nil), {[item.name] = 0}, owned,
            nil, {[item.name] = row})
          assert(item.enabled and owned[1] == nil, "an unlimited policy used the proof to invent a disablement")
        ''')

    def test_named_target_filters_only_its_own_queue_entries(self):
        self.lua.execute('''
          local belts = technology("recipe-prod-research_belts-1", 5, true)
          local braking = technology("braking-force-8", 8, true)
          local f = force(8, {[belts.name] = belts, [braking.name] = braking},
            {belts, braking}, belts, .33)
          local _, result = caps.reconcile(f, {[belts.name] = 4, [braking.name] = 7}, {},
            {[belts.name] = true})
          assert(result.queue_changed and #f.research_queue == 1
            and f.research_queue[1] == braking)
          assert(f.current_research == braking and f.research_progress == 0,
            "the native queue replacement owns cancellation of only the selected current research")
          assert(not belts.enabled and braking.enabled,
            "a named reconciliation changed another family")
        ''')

    def test_unavailable_entries_cancel_into_native_saved_work_without_a_queue_journal(self):
        self.lua.execute('''
          for _, progress in ipairs({0, .42, .999999}) do
            local bronze = technology("bronze", 5, false)
            local tin = technology("tin", 5, false)
            local lead = technology("lead", 5, true)
            local first, second = technology("automation", 1, true), technology("other", 1, true)
            bronze.saved_progress, tin.saved_progress, lead.saved_progress = 0, .17, .27
            local f = force(1, {bronze=bronze,tin=tin,lead=lead,automation=first,other=second},
              {bronze,bronze,first,tin,second}, bronze, progress)
            f.research_enabled = true
            f.disable_research = function() error("force-wide research pause") end
            f.enable_research = function() error("force-wide research switch") end
            local result = caps.remove_unavailable_from_queue(f, {bronze=true,tin=true})
            assert(result.queue_changed and result.removed_current == "bronze")
            assert(f.current_research == first and f.research_progress == 0,
              "cancelled investment must not transfer to unrelated current research")
            assert(#f.research_queue == 2 and f.research_queue[1] == first and f.research_queue[2] == second)
            assert(bronze.saved_progress == progress and lead.saved_progress == .27 and tin.saved_progress == .17)
            assert(bronze.level == 5 and not bronze.researched and not bronze.enabled and f.research_enabled)
            assert(f.worker_robots_speed_modifier == 7.15)
            result = caps.remove_unavailable_from_queue(f, {bronze=true,tin=true})
            assert(not result.queue_changed and bronze.saved_progress == progress)
          end
        ''')

    def test_unavailable_future_entry_keeps_eligible_current_order_and_progress(self):
        self.lua.execute('''
          local current, bronze, last = technology("current",1,true), technology("bronze",5,false),
            technology("last",1,true)
          current.saved_progress, bronze.saved_progress = .12, .27
          local f = force(1, {current=current,bronze=bronze,last=last}, {current,bronze,last}, current, .31)
          local result = caps.remove_unavailable_from_queue(f, {bronze=true})
          assert(result.queue_changed and result.removed_current == nil)
          assert(f.current_research == current and f.research_progress == .31)
          assert(current.saved_progress == .12 and bronze.saved_progress == .27)
          assert(#f.research_queue == 2 and f.research_queue[1] == current and f.research_queue[2] == last)
          assert(not caps.remove_unavailable_from_queue(f, {}).queue_changed)
        ''')

    def test_native_dropping_an_unselected_queue_entry_cannot_be_reported_preserved(self):
        self.lua.execute('''
          local bronze, foreign = technology("bronze",5,false), technology("foreign",1,false)
          local f = force(1, {bronze=bronze,foreign=foreign}, {bronze,foreign}, bronze, .42)
          local native_set = getmetatable(f).__newindex
          getmetatable(f).__newindex = function(self, key, value)
            if key == "research_queue" then value = {} end
            native_set(self, key, value)
          end
          local ok, message = pcall(caps.remove_unavailable_from_queue, f, {bronze=true})
          assert(not ok and tostring(message):find("dropped unselected research",1,true))
          assert(foreign.level == 1 and not foreign.enabled and not foreign.researched)
        ''')

    def test_unrepresentable_current_work_refuses_before_queue_cancellation(self):
        self.lua.execute('''
          for _, progress in ipairs({-1, 1, math.huge, 0/0}) do
            local bronze = technology("bronze",5,false)
            local original = {bronze}
            local f = force(1, {bronze=bronze}, original, bronze, progress)
            local ok, message = pcall(caps.remove_unavailable_from_queue, f, {bronze=true})
            assert(not ok and tostring(message):find("cannot preserve",1,true))
            assert(f.research_queue == original and f.current_research == bronze and bronze.level == 5)
          end
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
