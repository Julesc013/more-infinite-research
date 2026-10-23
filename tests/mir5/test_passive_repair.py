"""Pure Lua 5.2 controls for MIR5 passive-repair ownership, not native evidence."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PassiveRepairTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source/mir5").as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          repair = require("runtime.passive_repair")

          function force(name, index)
            local value = {name = name, index = index, valid = true, _friends = {}}
            value.get_friend = function(other) return value._friends[other.index] == true end
            return value
          end

          function game_with_forces()
            local player, ally, one_way, enemy, neutral = force("player", 1), force("ally", 2),
              force("one-way", 3), force("enemy", 4), force("neutral", 5)
            player._friends[2], ally._friends[1] = true, true
            player._friends[3] = true
            return {forces = {player = player}, tick = 0}, player, ally, one_way, enemy, neutral
          end

          function entity(id, owner, surface_index, health, maximum, kind)
            local raw = {health = health}
            local value = {
              valid = true, type = kind or "wall", unit_number = id, force = owner,
              surface = {index = surface_index or 1}, max_health = maximum or 10, writes = 0
            }
            return setmetatable(value, {
              __index = function(_, key) return raw[key] end,
              __newindex = function(self, key, replacement)
                if key ~= "health" then rawset(self, key, replacement); return end
                raw[key] = replacement
                rawset(self, "writes", self.writes + 1)
              end
            })
          end

          function damage(game, config, state, target, tick)
            return repair.on_entity_damaged(game, config, state, {entity = target, tick = tick})
          end
        ''')

    def test_only_player_or_reciprocal_friend_walls_and_gates_are_accepted(self):
        self.lua.execute('''
          local game, player, ally, one_way, enemy, neutral = game_with_forces()
          local config, state = {enabled = true}, nil
          state, first = damage(game, config, state, entity(1, player, 1, 5), 0)
          state, second = damage(game, config, state, entity(2, ally, 1, 5, 10, "gate"), 0)
          assert(first.accepted and second.accepted and #state.queue == 2 and state.scheduled)
          local _, one_way_result = damage(game, config, state, entity(3, one_way, 1, 5), 0)
          local _, enemy_result = damage(game, config, state, entity(4, enemy, 1, 5), 0)
          local _, neutral_result = damage(game, config, state, entity(5, neutral, 1, 5), 0)
          local _, type_result = damage(game, config, state, entity(6, player, 1, 5, 10, "container"), 0)
          assert(not one_way_result.accepted and not enemy_result.accepted
            and not neutral_result.accepted and not type_result.accepted)
          assert(#state.queue == 2 and state.members[3] == nil and state.members[6] == nil)
        ''')

    def test_known_unversioned_bucket_shape_with_lua_entity_members_remains_usable(self):
        self.lua.execute('''
          local game, player = game_with_forces()
          local retained = entity(9, player, 1, 4)
          local old_bucket = {
            queue = {9},
            members = {[9] = {entity = retained, force_index = 1, surface_index = 1,
              quiet_until = 0, next_repair_tick = 0}},
            scheduled = true,
            preserved_unknown_field = "keep"
          }
          local state, facts = repair.on_nth_tick(game, {enabled = true}, old_bucket, {tick = 0})
          assert(state == old_bucket and state.schema == nil and state.preserved_unknown_field == "keep")
          assert(facts.repaired == 1 and retained.health == 5 and #state.queue == 1 and state.queue[1] == 9)
          assert(state.members[9].entity == retained and state.scheduled)
        ''')

    def test_repeated_damage_postpones_without_duplicates_and_repairs_at_rate_one(self):
        self.lua.execute('''
          local game, player = game_with_forces()
          local target = entity(1, player, 1, 5)
          local state = damage(game, {enabled = true}, nil, target, 0)
          local same, postponed = damage(game, {enabled = true}, state, target, 100)
          assert(same == state and postponed.accepted and postponed.postponed and #state.queue == 1)
          assert(state.members[1].quiet_until == 700 and state.members[1].next_repair_tick == 700)
          local _, too_early = repair.on_nth_tick(game, {enabled = true}, state, {tick = 600})
          assert(too_early.processed == 1 and too_early.repaired == 0 and target.health == 5)
          local _, first = repair.on_nth_tick(game, {enabled = true}, state, {tick = 700})
          assert(first.repaired == 1 and target.health == 6 and state.members[1].next_repair_tick == 760)
          local _, rate_limited = repair.on_nth_tick(game, {enabled = true}, state, {tick = 720})
          assert(rate_limited.repaired == 0 and target.health == 6)
          local _, second = repair.on_nth_tick(game, {enabled = true}, state, {tick = 760})
          assert(second.repaired == 1 and target.health == 7)
        ''')

    def test_ordered_queue_observes_eight_entity_budget_and_keeps_remainder_first(self):
        self.lua.execute('''
          local game, player = game_with_forces()
          local state, targets = nil, {}
          for id = 1, 10 do
            targets[id] = entity(id, player, 1, 1, 3)
            state = damage(game, {enabled = true}, state, targets[id], 0)
          end
          local _, facts = repair.on_nth_tick(game, {enabled = true}, state, {tick = 600})
          assert(facts.processed == 8 and facts.repaired == 8 and facts.needs_schedule)
          assert(#state.queue == 10 and state.queue[1] == 9 and state.queue[2] == 10)
          for index = 1, 8 do
            assert(state.queue[index + 2] == index and targets[index].health == 2)
          end
          assert(targets[9].health == 1 and targets[10].health == 1)
        ''')

    def test_pending_queue_is_capped_at_256(self):
        self.lua.execute('''
          local game, player = game_with_forces()
          local state
          for id = 1, 256 do
            state, facts = damage(game, {enabled = true}, state, entity(id, player, 1, 1), 0)
            assert(facts.accepted)
          end
          local same, overflow = damage(game, {enabled = true}, state, entity(257, player, 1, 1), 0)
          assert(same == state and not overflow.accepted and overflow.capacity_reached)
          assert(#state.queue == 256 and state.members[257] == nil)
        ''')

    def test_destroyed_force_changed_surface_changed_and_full_members_are_dropped(self):
        self.lua.execute('''
          local game, player, ally, _, enemy = game_with_forces()
          local destroyed, changed_force = entity(1, player, 1, 5), entity(2, ally, 1, 5)
          local changed_surface, healed = entity(3, player, 1, 5), entity(4, player, 1, 5, 9)
          local state
          state = damage(game, {enabled = true}, state, destroyed, 0)
          state = damage(game, {enabled = true}, state, changed_force, 0)
          state = damage(game, {enabled = true}, state, changed_surface, 0)
          state = damage(game, {enabled = true}, state, healed, 0)
          destroyed.valid = false
          changed_force.force = enemy
          changed_surface.surface = {index = 2}
          healed.health = 9 -- an external full repair before MIR's turn
          local _, facts = repair.on_nth_tick(game, {enabled = true}, state, {tick = 600})
          assert(facts.processed == 4 and facts.repaired == 0 and facts.dropped == 4)
          assert(#state.queue == 0 and next(state.members) == nil and not state.scheduled)
          assert(healed.health == 9 and healed.writes == 1)
        ''')

    def test_disable_clears_state_readdition_is_fresh_and_on_load_is_read_only(self):
        self.lua.execute('''
          local game, player = game_with_forces()
          local state = damage(game, {enabled = true}, nil, entity(1, player, 1, 5), 0)
          state.scheduled = false
          local before_queue = state.queue
          local load = repair.on_load({enabled = true}, state)
          assert(load.active and load.needs_schedule and state.queue == before_queue and not state.scheduled)
          local cleared, stopped = repair.reconcile({enabled = false}, state)
          assert(cleared == state and stopped.cleared and not stopped.needs_schedule)
          assert(#state.queue == 0 and next(state.members) == nil and not state.scheduled)
          local readded, accepted = damage(game, {enabled = true}, state, entity(2, player, 1, 5), 10)
          assert(readded == state and accepted.accepted and #state.queue == 1 and state.queue[1] == 2)

          local poison = setmetatable({}, {__index = function(_, key)
            error("disabled repair read " .. tostring(key))
          end})
          local _, disabled = repair.on_entity_damaged(poison, {enabled = false}, state, poison)
          assert(not disabled.active and #state.queue == 0 and next(state.members) == nil)
          assert(not repair.on_load({enabled = false}, state).needs_schedule)
        ''')

    def test_source_has_no_registration_storage_or_retired_runtime_imports(self):
        source = (ROOT / "source/mir5/runtime/passive_repair.lua").read_text(encoding="utf-8")
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
        unittest.defaultTestLoader.loadTestsFromTestCase(PassiveRepairTests))
    sys.exit(0 if result.wasSuccessful() else 1)
