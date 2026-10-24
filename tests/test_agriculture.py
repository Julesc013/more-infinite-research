"""Pure Lua 5.2 controls for MIR5 agricultural-growth mutation, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AgricultureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          agriculture = require("runtime.agriculture")

          function force(name, level, valid)
            local technologies = {}
            if level ~= nil then technologies[agriculture.technology_name] = {level = level} end
            return {name = name, valid = valid ~= false, technologies = technologies}
          end

          function mock_game(forces, tick)
            return {forces = forces, tick = tick or 100}
          end

          function plant(owner, grown, valid, reject_write)
            local raw = {tick_grown = grown}
            local value = {valid = valid ~= false, force = owner, writes = 0}
            return setmetatable(value, {
              __index = function(_, key) return raw[key] end,
              __newindex = function(self, key, replacement)
                if key ~= "tick_grown" then rawset(self, key, replacement); return end
                if reject_write then error("native tick_grown write rejected") end
                raw[key] = replacement
                rawset(self, "writes", self.writes + 1)
              end
            })
          end
        ''')

    def test_refresh_preserves_old_bucket_shape_and_snapshots_two_non_enemy_forces(self):
        self.lua.execute('''
          local alpha, beta = force("alpha", 3), force("beta", 5)
          local game = mock_game({alpha = alpha, beta = beta,
            enemy = force("enemy", 40), neutral = force("neutral", 40)})
          local old_bucket = {force_multipliers = {old = {level = 7, multiplier = 2}}, keep = "legacy"}
          local state, facts = agriculture.refresh(game, {enabled = true, per_level_percent = 10}, old_bucket)
          assert(state == old_bucket and state.keep == "legacy" and state.schema == nil)
          assert(facts.active and facts.refreshed)
          assert(state.force_multipliers.alpha.level == 2 and state.force_multipliers.beta.level == 4)
          assert(math.abs(state.force_multipliers.alpha.multiplier - 1.21) < .0000001)
          assert(math.abs(state.force_multipliers.beta.multiplier - 1.4641) < .0000001)
          assert(state.force_multipliers.enemy == nil and state.force_multipliers.neutral == nil)
        ''')

    def test_tower_force_wins_and_invalid_tower_falls_back_to_plant_force(self):
        self.lua.execute('''
          local tower_force, plant_force = force("tower", 5), force("plant", 3)
          local game = mock_game({}, 100)
          local planted = plant(plant_force, 200)
          local state, result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = true, force = tower_force}, plant = planted, tick = 100})
          assert(state == nil and result.applied and result.level == 4)
          assert(planted.tick_grown == 168 and planted.writes == 1)

          local fallback = plant(plant_force, 200)
          local _, fallback_result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = false, force = tower_force}, plant = fallback, tick = 100})
          assert(fallback_result.applied and fallback_result.level == 2)
          assert(fallback.tick_grown == 182 and fallback.writes == 1)
        ''')

    def test_research_reversal_reads_current_force_not_a_stale_snapshot(self):
        self.lua.execute('''
          local owner = force("agriculture", 4)
          local game = mock_game({}, 100)
          local state = agriculture.refresh(mock_game({agriculture = owner}), {
            enabled = true, per_level_percent = 10
          }, nil)
          local before = plant(owner, 200)
          local _, first = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, state,
            {tower = {valid = true, force = owner}, plant = before, tick = 100})
          assert(first.applied and first.level == 3 and before.tick_grown == 175)

          owner.technologies[agriculture.technology_name].level = 2
          local after = plant(owner, 200)
          local _, reversed = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, state,
            {tower = {valid = true, force = owner}, plant = after, tick = 100})
          assert(reversed.applied and reversed.level == 1 and after.tick_grown == 190)
          assert(state.force_multipliers.agriculture.level == 3)
        ''')

    def test_fractional_remainder_uses_one_tick_minimum_and_multiplier_is_capped(self):
        self.lua.execute('''
          local owner = force("agriculture", 10)
          local game = mock_game({}, 100)
          local almost_grown = plant(owner, 102)
          local _, result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 100}, nil,
            {tower = {valid = true, force = owner}, plant = almost_grown, tick = 100})
          assert(result.applied and result.multiplier == 10 and almost_grown.tick_grown == 101)
          local one_tick = plant(owner, 101)
          local _, unchanged = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 100}, nil,
            {tower = {valid = true, force = owner}, plant = one_tick, tick = 100})
          assert(not unchanged.applied and unchanged.reason == "already-growing" and one_tick.writes == 0)
        ''')

    def test_invalid_plant_native_read_and_native_write_failures_do_not_escape_or_mutate(self):
        self.lua.execute('''
          local owner = force("agriculture", 2)
          local game = mock_game({}, 100)
          local invalid = setmetatable({valid = false, force = owner}, {
            __index = function(_, key) error("invalid plant read " .. tostring(key)) end
          })
          local _, invalid_result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = true, force = owner}, plant = invalid, tick = 100})
          assert(not invalid_result.applied and invalid_result.reason == "invalid-plant")

          local unreadable = setmetatable({valid = true, force = owner}, {
            __index = function(_, key)
              if key == "tick_grown" then error("native tick_grown read rejected") end
            end
          })
          local _, read_result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = true, force = owner}, plant = unreadable, tick = 100})
          assert(not read_result.applied and read_result.reason == "tick-grown-unreadable")

          local unwritable = plant(owner, 200, true, true)
          local _, write_result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = true, force = owner}, plant = unwritable, tick = 100})
          assert(not write_result.applied and write_result.reason == "tick-grown-write-failed")
          assert(unwritable.tick_grown == 200 and unwritable.writes == 0)
        ''')

    def test_missing_research_does_not_read_or_write_the_plant(self):
        self.lua.execute('''
          local no_research = force("agriculture", nil)
          local game = mock_game({}, 100)
          local plant_probe = setmetatable({valid = true, force = no_research}, {
            __index = function(_, key) error("missing research read " .. tostring(key)) end,
            __newindex = function(_, key) error("missing research write " .. tostring(key)) end
          })
          local _, result = agriculture.on_tower_planted_seed(game,
            {enabled = true, per_level_percent = 10}, nil,
            {tower = {valid = true, force = no_research}, plant = plant_probe, tick = 100})
          assert(not result.applied and result.reason == "missing-research")
        ''')

    def test_disabled_path_does_not_access_game_or_event_and_clears_existing_snapshot_once(self):
        self.lua.execute('''
          local poison = setmetatable({}, {__index = function(_, key)
            error("disabled agriculture read " .. tostring(key))
          end})
          local legacy = {force_multipliers = {alpha = {level = 3, multiplier = 1.3}}}
          local untouched, facts = agriculture.on_tower_planted_seed(poison,
            {enabled = false}, legacy, poison)
          assert(untouched == legacy and not facts.active and not facts.applied)
          assert(legacy.force_multipliers.alpha.level == 3)
          local refreshed, stopped = agriculture.refresh(poison, {enabled = false}, legacy)
          assert(refreshed == legacy and not stopped.active and next(legacy.force_multipliers) == nil)
        ''')

    def test_source_has_no_registration_storage_or_retired_runtime_imports(self):
        source = (ROOT / "source/runtime/agriculture.lua").read_text(encoding="utf-8")
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
        unittest.defaultTestLoader.loadTestsFromTestCase(AgricultureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
