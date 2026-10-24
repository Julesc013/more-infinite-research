"""Host controls for the private F200 passive-repair queue-bound fixture.

These controls exercise only the fixture's native-shaped boundary checks.  A
Black Glass run is still required to establish native repair scheduling.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "mir5" / "fixtures" / "repair-stress"
CONTROL = FIXTURE / "control.lua"
SETTINGS_UPDATE = FIXTURE / "settings-updates.lua"
NAME = "mir-fixture-mir5-repair-stress"
VARIANTS = {
    "published": ("4.7.20002", "0.1.0"),
    "mir5": ("5.0.20000", "0.2.0"),
}


class RepairStressFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(r'''
function repair_stress_settings(path, present, default_value)
  local raw = {['bool-setting'] = {}}
  if present then raw['bool-setting']['mir-enable-passive-repair'] = {default_value = default_value} end
  local env = {data = {raw = raw}}
  env._G = env
  setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message)
  local ok, result = pcall(chunk)
  return {ok = ok, message = tostring(result), raw = raw}
end

function repair_stress_parse(path, mir, fixture, enabled, state)
  local callbacks, reads, writes = {}, {}, 0
  local storage = setmetatable({}, {
    __index = function(_, key)
      if key == 'mir5_repair_stress' then return state end
      return nil
    end,
    __newindex = function() writes = writes + 1; error('control parse wrote fixture storage') end
  })
  local env = {
    script = {
      active_mods = {base = '2.0.77', ['more-infinite-research'] = mir,
        ['mir-fixture-mir5-repair-stress'] = fixture},
      on_init = function(callback) callbacks.init = callback end,
      on_load = function(callback) callbacks.load = callback end,
      on_event = function(event, callback) callbacks[event] = callback end
    },
    defines = {events = {on_tick = 1}},
    settings = {startup = {['mir-enable-passive-repair'] = {value = enabled}}},
    storage = storage,
    helpers = {table_to_json = function() return '{}' end},
    log = function() end
  }
  env._G = env
  setmetatable(env, {__index = function(_, key)
    if key == 'game' then reads.game = (reads.game or 0) + 1; return nil end
    return _G[key]
  end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message)
  local ok, result = pcall(chunk)
  return {ok = ok, message = tostring(result), callbacks = callbacks, reads = reads, writes = writes}
end

function repair_stress_load(path)
  local callbacks, writes = {}, 0
  local state = {phase = 'completed', mode = 'mir5-5.0.20000',
    initial_record = {changed = 256, first_service_tick = 600},
    reactivation_record = {changed = 8, first_service_tick = 3120}}
  local storage = setmetatable({}, {
    __index = function(_, key) assert(key == 'mir5_repair_stress'); return state end,
    __newindex = function() writes = writes + 1; error('on_load wrote durable fixture storage') end
  })
  local poisoned_game = setmetatable({}, {__index = function() error('on_load accessed game') end})
  local env = {
    script = {active_mods = {}, on_init = function() end, on_load = function(callback) callbacks.load = callback end,
      on_event = function() end},
    defines = {events = {on_tick = 1}}, settings = {}, storage = storage, game = poisoned_game,
    helpers = {table_to_json = function() return '{}' end}, log = function() end
  }
  env._G = env
  setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message); chunk()
  local ok, result = pcall(callbacks.load)
  return {ok = ok, message = tostring(result), writes = writes}
end

function repair_stress_observer_opponent(path, opponent)
  local callbacks, storage = {}, {}
  local next_unit, next_force = 0, 10
  local function make_force(name, index)
    local friends = {}
    local value = {name = name, index = index, valid = true}
    value.set_friend = function(other, friend) friends[other.index] = friend end
    value.get_friend = function(other) return friends[other.index] == true end
    return value
  end
  local player, enemy = make_force('player', 1), make_force('enemy', 2)
  local forces = {player = player, enemy = enemy, [1] = player, [2] = enemy}
  local game = {tick = 0, forces = forces, surfaces = {}}
  game.server_save = function(name) assert(name == 'mir5-native-complete') end
  game.create_force = function(name)
    next_force = next_force + 1
    local value = make_force(name, next_force)
    forces[name], forces[value.index] = value, value
    return value
  end
  local surface = {valid = true}
  surface.create_entity = function(spec)
    next_unit = next_unit + 1
    local entity = {
      valid = true, type = spec.name == 'stone-wall' and 'wall' or 'container', force = spec.force,
      unit_number = next_unit, health = 350, max_health = 350
    }
    entity.damage = function(amount, force, kind)
      assert(amount == 1 and force == enemy and kind == 'electric')
      entity.health = entity.health - 1
      return 1
    end
    return entity
  end
  game.surfaces[1] = surface
  local env = {
    script = {
      active_mods = {base = '2.0.77', ['more-infinite-research'] = '5.0.20000',
        ['mir-fixture-mir5-repair-stress'] = '0.2.0'},
      on_init = function(callback) callbacks.init = callback end,
      on_load = function(callback) callbacks.load = callback end,
      on_event = function(event, callback) callbacks.tick = callback end
    },
    defines = {events = {on_tick = 1}}, game = game, storage = storage,
    settings = {startup = {['mir-enable-passive-repair'] = {value = true}}},
    helpers = {table_to_json = function() return '{}' end}, log = function() end
  }
  env._G = env
  setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message); assert(pcall(chunk)); assert(pcall(callbacks.init))
  local state = storage.mir5_repair_stress
  if opponent == 'reactivation-alignment' then
    for index = 1, 256 do
      state.eligible[index].entity.health = state.eligible[index].maximum
      state.eligible[index].observed_health = state.eligible[index].maximum
    end
    state.initial_record = {changed = 256, services = 32, maximum_batch = 8,
      first_observed_tick = 601, first_service_tick = 600}
    for index = 1, 8 do
      state.eligible[index].entity.health = state.eligible[index].maximum - 1
      state.eligible[index].observed_health = state.eligible[index].maximum - 1
    end
    state.reactivation_tick = 2461
    state.reactivation_record = {changed = 0, services = 0, maximum_batch = 0}
    state.deadline_tick = 4000
    state.phase = 'await-reactivation'
    game.tick = 3121 -- observes the service aligned at tick 3120.
    for index = 1, 8 do state.eligible[index].entity.health = state.eligible[index].maximum end
    local ok, result = pcall(callbacks.tick)
    return {ok = ok, message = tostring(result), phase = state.phase,
      reactivation_service = state.reactivation_record.first_service_tick,
      reactivation_observed = state.reactivation_record.first_observed_tick}
  end
  local changed = opponent == 'batch' and 9 or 1
  for index = 1, changed do state.eligible[index].entity.health = state.eligible[index].entity.health + 1 end
  game.tick = opponent == 'batch' and 601 or 599
  local ok, result = pcall(callbacks.tick)
  return {ok = ok, message = tostring(result), total = #state.eligible,
    player = state.player_primary, friendly = state.friendly_primary,
    overflow = #state.eligible - 256, damage_calls = next_unit}
end
''')

    def test_metadata_variants_pin_the_same_fixture_identity_and_exact_f200_mir(self):
        for directory, (mir, version) in VARIANTS.items():
            with self.subTest(directory=directory):
                info = json.loads((FIXTURE / directory / "info.json").read_text(encoding="utf-8"))
                self.assertEqual((NAME, version, "2.0"), (info["name"], info["version"], info["factorio_version"]))
                self.assertEqual(
                    ["base >= 2.0.77", f"more-infinite-research = {mir}"], info["dependencies"]
                )

    def test_native_shaped_settings_stage_precedes_runtime_setting_and_rejects_absence_or_drift(self):
        path = str(SETTINGS_UPDATE)
        selected = self.lua.eval("repair_stress_settings")(path, True, False)
        self.assertTrue(selected["ok"], selected["message"])
        self.assertTrue(selected["raw"]["bool-setting"]["mir-enable-passive-repair"]["default_value"])
        for present, default, phrase in (
            (False, False, "startup setting is absent or changed"),
            (True, True, "startup setting is absent or changed"),
        ):
            with self.subTest(present=present, default=default):
                observed = self.lua.eval("repair_stress_settings")(path, present, default)
                self.assertFalse(observed["ok"])
                self.assertIn(phrase, observed["message"])

        source = CONTROL.read_text(encoding="utf-8")
        self.assertNotIn("data.raw", source)
        # repair_stress_parse supplies no data table: settings prototypes exist
        # only during settings stage, while control sees settings.startup.
        parsed = self.lua.eval("repair_stress_parse")(str(CONTROL), "5.0.20000", "0.2.0", True, None)
        self.assertTrue(parsed["ok"], parsed["message"])
        self.assertEqual({}, dict(parsed["reads"].items()))
        self.assertEqual(0, parsed["writes"])
        self.assertIsNotNone(parsed["callbacks"]["init"])
        self.assertIsNotNone(parsed["callbacks"]["load"])
        self.assertIsNotNone(parsed["callbacks"][1])

    def test_runtime_false_setting_rejects_before_entity_setup(self):
        parsed = self.lua.eval("repair_stress_parse")(str(CONTROL), "5.0.20000", "0.2.0", False, None)
        self.assertTrue(parsed["ok"], parsed["message"])
        callback = parsed["callbacks"]["init"]
        # This parse-only environment has no game; a correct mode/setting guard
        # must reject the false runtime setting before attempting native setup.
        ok, message = self.lua.eval("pcall")(callback)
        self.assertFalse(ok)
        self.assertIn("runtime setting is not enabled", message)

    def test_fixture_observer_rejects_early_or_over_budget_native_health_changes(self):
        run = self.lua.eval("repair_stress_observer_opponent")
        for opponent, phrase in (
            ("early", "repaired before the quiet period"),
            ("batch", "observed repair batch exceeded eight entities"),
        ):
            with self.subTest(opponent=opponent):
                observed = run(str(CONTROL), opponent)
                self.assertFalse(observed["ok"])
                self.assertIn(phrase, observed["message"])
                self.assertEqual((1000, 128, 128, 744),
                    (observed["total"], observed["player"], observed["friendly"], observed["overflow"]))
                # 1,000 eligible walls, two foreign walls, and a non-wall all
                # had to receive native-shaped damage through LuaEntity.damage.
                self.assertEqual(1003, observed["damage_calls"])

        # The re-damage happens after the initial queue drained between global
        # 60-tick subscriptions.  The fixture must report the actual next
        # aligned service (3120), rather than treating 2461 + 600 as aligned.
        aligned = run(str(CONTROL), "reactivation-alignment")
        self.assertTrue(aligned["ok"], aligned["message"])
        self.assertEqual(("completed", 3120, 3121),
                         (aligned["phase"], aligned["reactivation_service"], aligned["reactivation_observed"]))

    def test_load_callback_is_scalar_read_only_and_fixture_keeps_the_bounded_contract_visible(self):
        loaded = self.lua.eval("repair_stress_load")(str(CONTROL))
        self.assertTrue(loaded["ok"], loaded["message"])
        self.assertEqual(0, loaded["writes"])

        source = CONTROL.read_text(encoding="utf-8")
        on_load = source.split("script.on_load(function()", 1)[1].split("script.on_event", 1)[0]
        self.assertNotIn("game.", on_load)
        self.assertNotRegex(on_load, r"storage\s*\[.*?\]\s*=")
        for token in (
            "TOTAL = 1000", "CAPACITY = 256", "OVERFLOW = TOTAL - CAPACITY", "BUDGET = 8",
            "QUIET_TICKS = 600", "SERVICE_TICKS = 60", "REACTIVATE_COUNT = 8",
            'entity.damage(DAMAGE_AMOUNT, game.forces.enemy, DAMAGE_TYPE)',
            'DAMAGE_TYPE = "electric"',
            "friendly.set_friend(player, true)", "player.set_friend(friendly, true)",
            "assert_overflow_and_sentinels", "redamage_drained_queue", "marker(\"initial\"", "marker(\"reload\"",
            "performance_qualified = false", "runtime_elapsed_qualified = false",
        ):
            with self.subTest(token=token):
                self.assertIn(token, source)
        for forbidden in ("storage.mir", "require(", "game.create_player", "on_nth_tick", "reset_technology_effects"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RepairStressFixtureTests)
    )
    raise SystemExit(0 if result.wasSuccessful() else 1)
