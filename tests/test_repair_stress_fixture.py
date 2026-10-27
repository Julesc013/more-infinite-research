"""Host controls for the private F200/F210 passive-repair queue-bound fixture.

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
FIXTURE = ROOT / "tests" / "fixtures" / "repair-stress"
CONTROL = FIXTURE / "control.lua"
SETTINGS_UPDATE = FIXTURE / "settings-updates.lua"
NAME = "mir-fixture-mir5-repair-stress"
PROFILE_ROOT = ROOT / "tests" / "profiles"
F200_ENGINE = {
    "version": "2.0.77",
    "sha256": "D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B",
}
F210_ENGINE = {
    "version": "2.1.23",
    "sha256": "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060",
}
F200_OBSERVER = "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87"
F210_OBSERVER = "2E1BE5952D2A4CC5C74A0D149E075D247BA110A3FAE5B6768D3EAEBABCEF989C"
F210_PUBLISHED = "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F"
F210_ACTIVE_CANDIDATE = "4F5BEE023930666FC0F921136A69B59861741BE44C311E03D46347D42018ECBC"


def fixture_role(arm):
    return "successor" if arm == "mir5" else arm
VARIANTS = {
    "f200": {
        "published": {
            "mir": "4.7.20002", "fixture": "0.1.0", "factorio": "2.0", "engine": F200_ENGINE,
            "info": "info.json", "profile": "repair-stress-published-f200-2077.json",
            "dependencies": ["base >= 2.0.77", "more-infinite-research = 4.7.20002"],
            "official": [("base", "2.0.77", True)], "observer": F200_OBSERVER,
            "archives": {"mir-fixture-mir5-active-mods-observer_0.1.0.zip": F200_OBSERVER},
        },
        "mir5": {
            "mir": "5.0.20000", "fixture": "0.2.0", "factorio": "2.0", "engine": F200_ENGINE,
            "info": "info.json", "profile": "repair-stress-mir5-f200-2077.json",
            "dependencies": ["base >= 2.0.77", "more-infinite-research = 5.0.20000"],
            "official": [("base", "2.0.77", True)], "observer": F200_OBSERVER,
            "archives": {"mir-fixture-mir5-active-mods-observer_0.1.0.zip": F200_OBSERVER},
        },
    },
    "f210": {
        "published": {
            "mir": "4.7.21002", "fixture": "0.1.0", "factorio": "2.1", "engine": F210_ENGINE,
            "info": "info-f210.json", "profile": "repair-stress-published-f210-2123.json",
            "dependencies": ["base = 2.1.23", "space-age = 2.1.23", "more-infinite-research = 4.7.21002"],
            "official": [("base", "2.1.23", True), ("elevated-rails", "2.1.23", True),
                         ("quality", "2.1.23", True), ("recycler", "2.1.23", True),
                         ("space-age", "2.1.23", True)],
            "observer": F210_OBSERVER,
            "archives": {"more-infinite-research_4.7.21002.zip": F210_PUBLISHED,
                         "mir-fixture-mir5-active-mods-observer_0.1.0.zip": F210_OBSERVER},
        },
        "mir5": {
            "mir": "5.0.21000", "fixture": "0.2.0", "factorio": "2.1", "engine": F210_ENGINE,
            "info": "info-f210.json", "profile": "repair-stress-mir5-f210-2123.json",
            "dependencies": ["base = 2.1.23", "space-age = 2.1.23", "more-infinite-research = 5.0.21000"],
            "official": [("base", "2.1.23", True), ("elevated-rails", "2.1.23", True),
                         ("quality", "2.1.23", True), ("recycler", "2.1.23", True),
                         ("space-age", "2.1.23", True)],
            "observer": F210_OBSERVER,
            "archives": {"mir-fixture-mir5-active-mods-observer_0.1.0.zip": F210_OBSERVER},
        },
    },
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

function repair_stress_mode_guard(path, base, rails, quality, recycler, space, mir, fixture)
  local callbacks = {}
  local active = {base = base, ['more-infinite-research'] = mir,
    ['mir-fixture-mir5-repair-stress'] = fixture}
  if rails ~= nil then active['elevated-rails'] = rails end
  if quality ~= nil then active.quality = quality end
  if recycler ~= nil then active.recycler = recycler end
  if space ~= nil then active['space-age'] = space end
  local env = {
    script = {
      active_mods = active,
      on_init = function(callback) callbacks.init = callback end,
      on_load = function() end,
      on_event = function() end
    },
    defines = {events = {on_tick = 1}},
    settings = {startup = {['mir-enable-passive-repair'] = {value = false}}},
    storage = {}, helpers = {table_to_json = function() return '{}' end}, log = function() end
  }
  env._G = env
  setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message); chunk()
  local ok, result = pcall(callbacks.init)
  return {ok = ok, message = tostring(result)}
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

function repair_stress_observer_opponent(path, opponent, active)
  local callbacks, storage, reports, saves = {}, {}, {}, {}
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
  game.server_save = function(name) saves[#saves + 1] = name end
  game.create_force = function(name)
    next_force = next_force + 1
    local value = make_force(name, next_force)
    forces[name], forces[value.index] = value, value
    return value
  end
  local damage_calls = 0
  local surface = {valid = true}
  surface.create_entity = function(spec)
    next_unit = next_unit + 1
    local entity = {
      valid = true, type = spec.name == 'stone-wall' and 'wall' or 'container', force = spec.force,
      unit_number = next_unit, health = 350, max_health = 350
    }
    entity.damage = function(amount, force, kind)
      assert(amount == 1 and force == enemy and kind == 'electric')
      damage_calls = damage_calls + 1
      entity.health = entity.health - 1
      return 1
    end
    return entity
  end
  game.surfaces[1] = surface
  local active_mods = active and {
    base = '2.1.23', ['elevated-rails'] = '2.1.23', quality = '2.1.23', recycler = '2.1.23',
    ['space-age'] = '2.1.23', ['more-infinite-research'] = '5.0.21000',
    ['mir-fixture-mir5-repair-stress'] = '0.2.0',
    ['mir-fixture-mir5-repair-stress-active'] = '0.1.0'
  } or {
    base = '2.0.77', ['more-infinite-research'] = '5.0.20000',
    ['mir-fixture-mir5-repair-stress'] = '0.2.0'
  }
  local env = {
    script = {
      active_mods = active_mods,
      on_init = function(callback) callbacks.init = callback end,
      on_load = function(callback) callbacks.load = callback end,
      on_event = function(event, callback) callbacks.tick = callback end
    },
    defines = {events = {on_tick = 1}}, game = game, storage = storage,
    settings = {startup = {['mir-enable-passive-repair'] = {value = true}}},
    helpers = {table_to_json = function(row) reports[#reports + 1] = row; return '{}' end}, log = function() end
  }
  env._G = env
  setmetatable(env, {__index = function(_, key) return _G[key] end})
  local chunk, message = loadfile(path, 't', env)
  assert(chunk, message); assert(pcall(chunk)); assert(pcall(callbacks.init))
  local state = storage.mir5_repair_stress
  if active then
    local before = damage_calls
    if opponent == 'active-before-load' then
      game.tick = 1
      local pending_ok, pending_message = pcall(callbacks.tick)
      return {ok = pending_ok, message = tostring(pending_message), phase = state.phase,
        damage_before_load = before, damage_after_start = damage_calls, saves = saves, reports = reports}
    end
    local load_ok, load_message = pcall(callbacks.load)
    game.tick = 1
    local start_ok, start_message = pcall(callbacks.tick)
    return {ok = load_ok and start_ok, message = load_ok and tostring(start_message) or tostring(load_message),
      phase = state.phase, entities = next_unit, damage_before_load = before, damage_after_start = damage_calls,
      saves = saves, reports = reports, total = #state.eligible, player = state.player_primary,
      friendly = state.friendly_primary, overflow = #state.eligible - 256}
  end
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
    overflow = #state.eligible - 256, damage_calls = damage_calls}
end
''')

    def test_metadata_profiles_and_shared_control_pin_exact_target_arms(self):
        for target, variants in VARIANTS.items():
            for arm, expected in variants.items():
                with self.subTest(target=target, arm=arm):
                    info = json.loads((FIXTURE / fixture_role(arm) / expected["info"]).read_text(encoding="utf-8"))
                    self.assertEqual(
                        (NAME, expected["fixture"], expected["factorio"]),
                        (info["name"], info["version"], info["factorio_version"]),
                    )
                    self.assertEqual(expected["dependencies"], info["dependencies"])

                    profile = json.loads((PROFILE_ROOT / expected["profile"]).read_text(encoding="utf-8"))
                    self.assertEqual(
                        ("mir5-repair-stress" + ("-f210" if target == "f210" else "") + "-native-selection", target,
                         expected["factorio"], expected["engine"]),
                        (profile["kind"], profile["target"], profile["factorio_line"], profile["engine"]),
                    )
                    self.assertEqual("Defaults", profile["settings_mode"])
                    self.assertEqual(expected["archives"], profile["archive_sha256"])
                    mods = [(entry["name"], entry["version"], entry["enabled"]) for entry in profile["mods"]]
                    self.assertEqual(
                        expected["official"] + [
                            ("mir-fixture-mir5-active-mods-observer", "0.1.0", True),
                            ("more-infinite-research", expected["mir"], True),
                            (NAME, expected["fixture"], True),
                        ],
                        mods,
                    )

        active_selector = FIXTURE / "active" / "info-f210.json"
        self.assertEqual(
            ("mir-fixture-mir5-repair-stress-active", "0.1.0", "2.1"),
            tuple(json.loads(active_selector.read_text(encoding="utf-8"))[key]
                  for key in ("name", "version", "factorio_version")),
        )
        for arm, mir, fixture, archive in (
            ("published", "4.7.21002", "0.1.0", F210_PUBLISHED),
            ("mir5", "5.0.21000", "0.2.0", F210_ACTIVE_CANDIDATE),
        ):
            with self.subTest(active_arm=arm):
                profile = json.loads((PROFILE_ROOT / f"repair-stress-active-{arm}-f210-2123.json")
                                     .read_text(encoding="utf-8"))
                self.assertEqual("mir5-active-repair-stress-f210-native-selection", profile["kind"])
                self.assertEqual(F210_ENGINE, profile["engine"])
                self.assertEqual(archive, profile["archive_sha256"]
                                 [f"more-infinite-research_{mir}.zip"])
                self.assertEqual(
                    ["base", "elevated-rails", "quality", "recycler", "space-age",
                     "mir-fixture-mir5-active-mods-observer", "more-infinite-research",
                     NAME, "mir-fixture-mir5-repair-stress-active"],
                    [row["name"] for row in profile["mods"]],
                )

        # A single shared runtime body must expose both accepted target arms;
        # the engine-specific info adapters choose the active-mod closure.
        source = CONTROL.read_text(encoding="utf-8")
        for token in (
            'active.base == "2.0.77"', 'active.base == "2.1.23"',
            'active["space-age"] == "2.1.23"', '"f210-published-4.7.21002"',
            '"f210-mir5-5.0.21000"', '"repair-stress-f210"', '"active-pending"',
            '"mir5-native-active"', '"[MIR5_RUNTIME_ACTIVE] "',
        ):
            with self.subTest(token=token):
                self.assertIn(token, source)

    def test_target_selector_admits_only_exact_f200_or_f210_metadata(self):
        guard = self.lua.eval("repair_stress_mode_guard")
        f210 = ("2.1.23", "2.1.23", "2.1.23", "2.1.23", "2.1.23")
        for args in (
            ("2.0.77", None, None, None, None, "4.7.20002", "0.1.0"),
            ("2.0.77", None, None, None, None, "5.0.20000", "0.2.0"),
            (*f210, "4.7.21002", "0.1.0"),
            (*f210, "5.0.21000", "0.2.0"),
        ):
            with self.subTest(args=args):
                observed = guard(str(CONTROL), *args)
                self.assertFalse(observed["ok"])
                self.assertIn("runtime setting is not enabled", observed["message"])

        for args, phrase in (
            (("2.1.23", "2.1.23", None, "2.1.23", "2.1.23", "5.0.21000", "0.2.0"), "official closure"),
            (("2.0.77", None, None, None, "2.1.23", "4.7.20002", "0.1.0"), "official closure"),
            ((*f210, "5.0.20000", "0.2.0"), "target-matched"),
            (("2.0.77", None, None, None, None, "4.7.21002", "0.1.0"), "target-matched"),
        ):
            with self.subTest(args=args):
                observed = guard(str(CONTROL), *args)
                self.assertFalse(observed["ok"])
                self.assertIn(phrase, observed["message"])

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

    def test_active_f210_seed_defers_all_damage_until_the_first_post_load_tick(self):
        run = self.lua.eval("repair_stress_observer_opponent")
        observed = run(str(CONTROL), "active-start", True)
        self.assertTrue(observed["ok"], observed["message"])
        self.assertEqual((1000, 128, 128, 744),
                         (observed["total"], observed["player"], observed["friendly"], observed["overflow"]))
        self.assertEqual(1003, observed["entities"])
        self.assertEqual(0, observed["damage_before_load"])
        self.assertEqual(1003, observed["damage_after_start"])
        self.assertEqual("await-initial", observed["phase"])
        self.assertEqual(["mir5-native-active"], [observed["saves"][index]
                                                   for index in range(1, len(observed["saves"]) + 1)])
        reports = [observed["reports"][index] for index in range(1, len(observed["reports"]) + 1)]
        self.assertEqual(["prepared", "start"], [row["stage"] for row in reports])
        self.assertTrue(reports[-1]["witnesses"]["pending_physical_work"])
        self.assertEqual(0, reports[-1]["witnesses"]["initial_changed"])

        before_load = run(str(CONTROL), "active-before-load", True)
        self.assertTrue(before_load["ok"], before_load["message"])
        self.assertEqual("active-pending", before_load["phase"])
        self.assertEqual(0, before_load["damage_before_load"])
        self.assertEqual(0, before_load["damage_after_start"])
        self.assertEqual(["mir5-native-active"], [before_load["saves"][index]
                                                    for index in range(1, len(before_load["saves"]) + 1)])
        pending_reports = [before_load["reports"][index]
                           for index in range(1, len(before_load["reports"]) + 1)]
        self.assertEqual(["prepared"], [row["stage"] for row in pending_reports])

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
