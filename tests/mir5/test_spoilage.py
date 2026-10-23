"""Pure Lua 5.2 controls for MIR5 spoilage contribution ownership, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SpoilageTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          spoilage = require("runtime.spoilage")

          function close(left, right)
            return math.abs(left - right) < .0000001
          end

          function technology(level)
            return {level = level}
          end

          function force(name, level)
            local technologies = {}
            if level ~= nil then
              technologies[spoilage.technology_name] = technology(level)
            end
            return {valid = true, name = name, technologies = technologies}
          end

          function mock_game(value, forces)
            local raw = {spoil_time_modifier = value}
            local settings = setmetatable({writes = 0}, {
              __index = function(_, key) return raw[key] end,
              __newindex = function(self, key, replacement)
                if key == "spoil_time_modifier" then
                  raw[key] = replacement
                  rawset(self, "writes", self.writes + 1)
                else
                  rawset(self, key, replacement)
                end
              end
            })
            return {forces = forces, difficulty_settings = settings}, settings
          end
        ''')

    def test_highest_eligible_level_is_global_not_per_force_or_enemy(self):
        self.lua.execute('''
          local game, difficulty = mock_game(2, {
            alpha = force("alpha", 3), beta = force("beta", 5),
            enemy = force("enemy", 99), neutral = force("neutral", 70)
          })
          local state, facts = spoilage.reconcile(game, {
            enabled = true, per_level_percent = 10
          }, nil)
          -- completed levels are 2 and 4; enemies and neutral do not contribute.
          assert(facts.active and facts.effective_level == 4)
          assert(close(difficulty.spoil_time_modifier, 2 * (1.1 ^ 4)))
          assert(close(state.baseline, 2) and close(state.applied_multiplier, 1.1 ^ 4))
          assert(close(state.last_applied_value, difficulty.spoil_time_modifier))
        ''')

    def test_external_global_write_is_rebased_but_reported_as_ambiguous(self):
        self.lua.execute('''
          local game, difficulty = mock_game(3, {alpha = force("alpha", 3)})
          local state, first = spoilage.reconcile(game, {
            enabled = true, per_level_percent = 10
          }, nil)
          assert(not first.external_write_ambiguous and close(difficulty.spoil_time_modifier, 3.63))

          -- This is an opponent write to the shared native aggregate. MIR can
          -- preserve the observed value through its own old multiplier, but
          -- cannot attribute who wrote it or reconstruct independent offsets.
          difficulty.spoil_time_modifier = 10
          local rebased, facts = spoilage.reconcile(game, {
            enabled = true, per_level_percent = 10
          }, state)
          assert(facts.external_write_ambiguous and close(rebased.baseline, 10 / 1.21))
          assert(close(difficulty.spoil_time_modifier, 10))
          assert(close(rebased.last_applied_value, 10) and close(rebased.applied_multiplier, 1.21))
        ''')

    def test_disable_restores_once_then_readdition_captures_new_baseline(self):
        self.lua.execute('''
          local game, difficulty = mock_game(4, {alpha = force("alpha", 2)})
          local state = spoilage.reconcile(game, {enabled = true, per_level_percent = 10}, nil)
          assert(close(difficulty.spoil_time_modifier, 4.4))
          local writes_before_disable = difficulty.writes

          local cleared, stopped = spoilage.reconcile(game, {enabled = false}, state)
          assert(cleared == nil and stopped.restored and not stopped.active)
          assert(close(difficulty.spoil_time_modifier, 4) and difficulty.writes == writes_before_disable + 1)
          local writes_after_restore = difficulty.writes
          local still_empty, again = spoilage.reconcile(game, {enabled = false}, cleared)
          assert(still_empty == nil and not again.restored and not again.active)
          assert(difficulty.writes == writes_after_restore)

          difficulty.spoil_time_modifier = 8
          local reapplied, active = spoilage.reconcile(game, {enabled = true, per_level_percent = 10}, nil)
          assert(active.active and close(reapplied.baseline, 8))
          assert(close(difficulty.spoil_time_modifier, 8.8))
        ''')

    def test_disable_never_overwrites_an_observed_foreign_value(self):
        self.lua.execute('''
          local game, difficulty = mock_game(5, {alpha = force("alpha", 2)})
          local state = spoilage.reconcile(game, {enabled = true, per_level_percent = 10}, nil)
          difficulty.spoil_time_modifier = 17
          local writes = difficulty.writes
          local cleared, stopped = spoilage.reconcile(game, {enabled = false}, state)
          assert(cleared == nil and stopped.external_write_ambiguous and not stopped.restored)
          assert(difficulty.spoil_time_modifier == 17 and difficulty.writes == writes)
        ''')

    def test_known_published_bucket_shape_has_no_schema_and_remains_usable(self):
        self.lua.execute('''
          local game, difficulty = mock_game(2.42, {alpha = force("alpha", 3)})
          -- Exact known 4.7 contribution fields: no schema/version wrapper.
          local old_bucket = {
            baseline = 2, effective_level = 2, applied_multiplier = 1.21,
            last_applied_value = 2.42
          }
          local state, facts = spoilage.reconcile(game, {
            enabled = true, per_level_percent = 10
          }, old_bucket)
          assert(state == old_bucket and state.schema == nil and facts.active)
          assert(close(difficulty.spoil_time_modifier, 2.42))
          assert(state.effective_level == 2 and close(state.applied_multiplier, 1.21))
        ''')

    def test_source_has_no_registration_settings_storage_or_retired_runtime_imports(self):
        source = (ROOT / "source/mir5/runtime/spoilage.lua").read_text(encoding="utf-8")
        self.assertNotIn("require(", source)
        self.assertNotIn("script.on_", source)
        self.assertNotIn("storage.", source)
        self.assertNotIn("prototypes.mir", source)
        self.assertNotIn("Generator", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SpoilageTests))
    sys.exit(0 if result.wasSuccessful() else 1)
