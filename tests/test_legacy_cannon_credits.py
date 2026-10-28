"""Independent controls for the bounded MIR 1.2 combined-cannon credit."""
import argparse
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = ROOT / "source/research/legacy_cannon_credit_definitions.lua"
RUNTIME = ROOT / "source/runtime/legacy_cannon_credits.lua"
UINT32_MAX = 4294967295


def py(value):
    if hasattr(value, "items"):
        pairs = list(value.items())
        keys = [key for key, _ in pairs]
        if keys and all(isinstance(key, int) and key > 0 for key in keys) and set(keys) == set(range(1, len(keys) + 1)):
            return [py(value[index]) for index in range(1, len(keys) + 1)]
        return {key: py(item) for key, item in pairs}
    return value


class LegacyCannonCreditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua.globals().definitions_path = DEFINITIONS.as_posix()
        cls.lua.globals().runtime_path = RUNTIME.as_posix()
        cls.lua.execute(r'''
          local UINT32_MAX = 4294967295

          local function native_technology(state)
            local proxy = {}
            return setmetatable(proxy, {
              __index = state,
              __newindex = function(_, key, value)
                state[key] = value
                state.writes[key] = (state.writes[key] or 0) + 1
                if key == "level" then state.enabled = true end
              end,
            })
          end

          local function public_rocket(level, researched, scalar, prototype_enabled, runtime_enabled)
            local state = {
              valid = true, name = "recipe-prod-research_rocket_shooting_speed-1",
              level = level, researched = researched, enabled = runtime_enabled,
              saved_progress = .27, writes = {},
              prototype = {
                name = "recipe-prod-research_rocket_shooting_speed-1", level = 1,
                max_level = UINT32_MAX, hidden = false, upgrade = true,
                enabled = prototype_enabled,
                effects = {{type = "gun-speed", ammo_category = "rocket", modifier = scalar}},
              },
            }
            return native_technology(state), state
          end

          local function holder(descriptor, scalar)
            local state = {
              valid = true, name = descriptor.id, level = 1, researched = false,
              enabled = false, visible_when_disabled = false, writes = {},
              research_unit_count = 1, research_unit_energy = 60,
              research_unit_ingredients = {{name = "automation-science-pack", amount = 1}},
              prototype = {
                name = descriptor.id, level = 1, max_level = UINT32_MAX,
                hidden = true, upgrade = true, enabled = false, visible_when_disabled = false,
                effects = {{type = "gun-speed", ammo_category = "cannon-shell", modifier = scalar}},
              },
            }
            return native_technology(state), state
          end

          local function force(index, level, researched, descriptor, scalar, prototype_enabled, runtime_enabled)
            local rocket, rocket_state = public_rocket(level, researched, scalar, prototype_enabled, runtime_enabled)
            local credit, credit_state = holder(descriptor, scalar)
            return {
              valid = true, index = index, technologies = {
                [descriptor.main_id] = rocket,
                [descriptor.id] = credit,
              },
              research_queue = {"preserved"}, research_progress = .42,
              rocket_state = rocket_state, holder_state = credit_state,
            }
          end

          function legacy_cannon_environment(target, scalar, prototype_enabled, runtime_enabled)
            local env = {storage = {}}
            env.script = {active_mods = {}}
            if target == "f200" then
              env.script.active_mods = {base = "2.0.77", ["more-infinite-research"] = "5.0.20000"}
            elseif target == "f200-forward" then
              env.script.active_mods = {base = "2.0.99", ["more-infinite-research"] = "5.0.20001"}
            elseif target == "f210" then
              env.script.active_mods = {base = "2.1.23", ["more-infinite-research"] = "5.0.21000"}
            elseif target == "f210-portal" then
              env.script.active_mods = {base = "2.1.23", ["more-infinite-research"] = "5.0.09"}
            elseif target == "f210-space-age" then
              env.script.active_mods = {base = "2.1.23", ["more-infinite-research"] = "5.0.21000", ["space-age"] = "2.0.77"}
            else error("unknown test target") end
            env.require = function(name)
              if name == "research.legacy_cannon_credit_definitions" then
                return assert(loadfile(definitions_path, "t", env))()
              end
              if name == "platform.target" then
                if target == "f200" then return {id = "f200", recipe_productivity = true, distribution_version = "5.0.20000"} end
                if target == "f200-forward" then return {id = "f200", recipe_productivity = true, distribution_version = "5.0.20001"} end
                if target == "f210-portal" then return {id = "f210", recipe_productivity = true, distribution_version = "5.0.09"} end
                return {id = "f210", recipe_productivity = true, distribution_version = "5.0.21000"}
              end
              error("unexpected module: " .. tostring(name))
            end
            env._G = env
            setmetatable(env, {__index = _G})
            local runtime = assert(loadfile(runtime_path, "t", env))()
            local descriptor = env.require("research.legacy_cannon_credit_definitions").descriptor()
            scalar = scalar == nil and .1 or scalar
            prototype_enabled = prototype_enabled == nil and true or prototype_enabled
            runtime_enabled = runtime_enabled == nil and prototype_enabled or runtime_enabled
            local player = force(1, 2, false, descriptor, scalar, prototype_enabled, runtime_enabled)
            local foreign = force(2, 2, false, descriptor, scalar, prototype_enabled, runtime_enabled)
            local detached = force(3, 1, false, descriptor, scalar, prototype_enabled, runtime_enabled)
            env.game = {forces = {player = player, foreign = foreign, detached = detached}}
            local event = {mod_changes = {
              ["more-infinite-research"] = {old_version = "1.2.0", new_version = env.script.active_mods["more-infinite-research"]},
            }}
            return {env = env, runtime = runtime, descriptor = descriptor, player = player,
              foreign = foreign, detached = detached, event = event}
          end

          function legacy_cannon_definition_rows()
            local definitions = assert(loadfile(definitions_path))()
            local target = {id = "f210", recipe_productivity = true}
            local rows = {{name = "recipe-prod-research_rocket_shooting_speed-1", effects = {
              {type = "gun-speed", ammo_category = "rocket", modifier = .23},
            }}}
            local first = definitions.append(rows, target)
            first[1].effects[1].modifier = .4
            local fresh = {{name = "recipe-prod-research_rocket_shooting_speed-1", effects = {
              {type = "gun-speed", ammo_category = "rocket", modifier = .23},
            }}}
            local second = definitions.append(fresh, target)
            local zero = {{name = "recipe-prod-research_rocket_shooting_speed-1", enabled = false, effects = {
              {type = "gun-speed", ammo_category = "rocket", modifier = 0},
            }}}
            local zero_rows = definitions.append(zero, target)
            return {first = first, second = second, zero = zero_rows, descriptor = definitions.descriptor()}
          end

          function legacy_cannon_success(target, scalar, level, old_version)
            local value = legacy_cannon_environment(target, scalar)
            if level then value.player.technologies[value.descriptor.main_id].level = level end
            if old_version then value.event.mod_changes["more-infinite-research"].old_version = old_version end
            local plan = value.runtime.preflight(value.event)
            assert(plan and #plan.forces == 2 and plan.target == (target:match("^f200") and "f200" or "f210"))
            assert(plan.forces[1].force == nil and plan.forces[2].force == nil)
            assert(value.runtime.apply(plan) == true)
            return {
              player = {holder = value.player.holder_state, rocket = value.player.rocket_state,
                state = value.player.holder_state},
              foreign = {holder = value.foreign.holder_state, state = value.foreign.holder_state},
              detached = {holder = value.detached.holder_state, state = value.detached.holder_state},
              second = value.runtime.on_configuration_changed(value.event),
              storage = value.env.storage,
            }
          end

          function legacy_cannon_reject(mutator)
            local value = legacy_cannon_environment("f210")
            mutator(value)
            local ok, message = pcall(value.runtime.preflight, value.event)
            return {ok = ok, message = tostring(message), player_writes = value.player.holder_state.writes.level or 0,
              foreign_writes = value.foreign.holder_state.writes.level or 0,
              detached_writes = value.detached.holder_state.writes.level or 0}
          end

          function legacy_cannon_apply_drift()
            local value = legacy_cannon_environment("f210")
            local plan = value.runtime.preflight(value.event)
            value.foreign.technologies[value.descriptor.id].prototype.effects[1].modifier = .2
            local ok, message = pcall(value.runtime.apply, plan)
            return {ok = ok, message = tostring(message), player = value.player.holder_state.writes.level or 0,
              foreign = value.foreign.holder_state.writes.level or 0}
          end

          function legacy_cannon_disabled_and_reset()
            local value = legacy_cannon_environment("f210", .37, false, false)
            local plan = value.runtime.preflight(value.event)
            assert(plan and value.runtime.apply(plan) == true)
            local holder = value.player.technologies[value.descriptor.id]
            holder.enabled, holder.visible_when_disabled = true, true
            local cleaned = value.runtime.on_technology_effects_reset({force = value.player})
            return {cleaned = cleaned, rocket_enabled = value.player.technologies[value.descriptor.main_id].enabled,
              rocket_level = value.player.technologies[value.descriptor.main_id].level,
              queue = value.player.research_queue[1], progress = value.player.research_progress,
               holder = value.player.holder_state, writes = value.player.holder_state.writes}
          end

          function legacy_cannon_zero_and_inactive()
            local zero = legacy_cannon_environment("f210", 0, false, false)
            local plan = zero.runtime.preflight(zero.event)
            assert(plan and zero.runtime.apply(plan) == true)
            local unknown = legacy_cannon_environment("f200")
            unknown.event.mod_changes["more-infinite-research"].old_version = "1.3.0"
            local no_plan = unknown.runtime.preflight(unknown.event)
            return {zero_scalar = zero.player.holder_state,
              zero_completed = zero.detached.holder_state,
              zero_completed_writes = zero.detached.holder_state.writes.level or 0,
              unknown = no_plan, unknown_writes = unknown.player.holder_state.writes.level or 0}
          end
        ''')

    def test_definition_stages_one_detached_cannon_holder_from_the_rocket_scalar(self):
        result = py(self.lua.eval("legacy_cannon_definition_rows")())
        self.assertEqual("mir-legacy-cannon-credit-rocket-shooting-speed", result["descriptor"]["id"])
        self.assertEqual(1, len(result["first"]))
        holder = result["second"][0]
        self.assertEqual((True, False, False, "infinite", 1, 1),
                         (holder["hidden"], holder["enabled"], holder["visible_when_disabled"],
                          holder["max_level"], holder["unit"]["count"], holder["unit"]["time"]))
        self.assertEqual(("gun-speed", "cannon-shell", .23),
                         (holder["effects"][0]["type"], holder["effects"][0]["ammo_category"],
                          holder["effects"][0]["modifier"]))
        self.assertEqual(0, result["zero"][0]["effects"][0]["modifier"])

    def test_exact_old_versions_credit_only_completed_combined_levels_for_both_modern_targets(self):
        for target in ("f200", "f200-forward", "f210", "f210-portal"):
            for old_version in ("1.2.0", "1.2.5", "1.2.9"):
                with self.subTest(target=target, old_version=old_version):
                    result = py(self.lua.eval("legacy_cannon_success")(target, .1, None, old_version))
                    self.assertEqual((2, False, False),
                                     (result["player"]["holder"]["level"], result["player"]["holder"]["enabled"],
                                      result["player"]["holder"]["visible_when_disabled"]))
                    self.assertEqual((2, False), (result["foreign"]["holder"]["level"], result["foreign"]["holder"]["enabled"]))
                    self.assertEqual(1, result["detached"]["holder"]["level"])
                    self.assertEqual((2, .27, "preserved"),
                                     (result["player"]["rocket"]["level"], result["player"]["rocket"]["saved_progress"],
                                      result["player"]["rocket"]["name"] and "preserved"))
                    self.assertFalse(result["second"])
                    self.assertEqual(1, result["player"]["state"]["writes"]["level"])

    def test_zero_and_multiple_completed_levels_and_custom_scalar_keep_the_public_row_unmodified(self):
        zero = py(self.lua.eval("legacy_cannon_zero_and_inactive")())
        self.assertEqual((2, False), (zero["zero_scalar"]["level"], zero["zero_scalar"]["enabled"]))
        self.assertEqual((1, False, 0),
                         (zero["zero_completed"]["level"], zero["zero_completed"]["enabled"], zero["zero_completed_writes"]))
        self.assertNotIn("unknown", zero)
        self.assertEqual(0, zero["unknown_writes"])

        multiple = py(self.lua.eval("legacy_cannon_success")("f210", .37, 4))
        self.assertEqual(4, multiple["player"]["holder"]["level"])
        self.assertEqual(4, multiple["player"]["rocket"]["level"])
        self.assertEqual(1, multiple["detached"]["holder"]["level"])

    def test_disabled_source_setting_shape_and_effect_reset_keep_public_state_and_clean_only_holder_flags(self):
        result = py(self.lua.eval("legacy_cannon_disabled_and_reset")())
        self.assertTrue(result["cleaned"])
        self.assertEqual((False, 2, "preserved", .42),
                         (result["rocket_enabled"], result["rocket_level"], result["queue"], result["progress"]))
        self.assertEqual((2, False, False),
                         (result["holder"]["level"], result["holder"]["enabled"], result["holder"]["visible_when_disabled"]))
        self.assertGreaterEqual(result["writes"]["level"], 1)

    def test_invalid_or_changed_named_shapes_reject_before_any_holder_write(self):
        cases = {
            "missing holder": 'function(value) value.player.technologies[value.descriptor.id] = nil end',
            "wrong scalar": 'function(value) value.foreign.technologies[value.descriptor.id].prototype.effects[1].modifier=.2 end',
            "foreign added effect": 'function(value) table.insert(value.player.technologies[value.descriptor.main_id].prototype.effects,{type="gun-speed",ammo_category="rocket",modifier=.1}) end',
            "changed source scalar": 'function(value) value.detached.technologies[value.descriptor.main_id].prototype.effects[1].modifier=-.1 end',
            "one tick holder": 'function(value) value.foreign.technologies[value.descriptor.id].research_unit_energy=1 end',
            "enabled holder": 'function(value) value.detached.technologies[value.descriptor.id].enabled=true end',
        }
        for label, mutation in cases.items():
            with self.subTest(label=label):
                result = py(self.lua.eval("legacy_cannon_reject")(self.lua.eval(mutation)))
                self.assertFalse(result["ok"])
                self.assertIn("non-current force shape", result["message"])
                self.assertEqual((0, 0, 0), (result["player_writes"], result["foreign_writes"], result["detached_writes"]))

        drift = py(self.lua.eval("legacy_cannon_apply_drift")())
        self.assertFalse(drift["ok"])
        self.assertIn("plan no longer matches", drift["message"])
        self.assertEqual((0, 0), (drift["player"], drift["foreign"]))

    def test_unknown_old_version_and_space_age_do_not_grant_credit(self):
        unknown = py(self.lua.eval("legacy_cannon_zero_and_inactive")())
        self.assertNotIn("unknown", unknown)
        self.assertEqual(0, unknown["unknown_writes"])
        self.lua.execute(r'''
          local value = legacy_cannon_environment("f210-space-age")
          assert(value.runtime.preflight(value.event) == nil)
          assert((value.player.holder_state.writes.level or 0) == 0)
        ''')

    def test_runtime_remains_one_time_named_carrier_logic_without_storage_or_ordinary_research_work(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn('require("research.legacy_cannon_credit_definitions")', source)
        self.assertNotIn("storage", source)
        self.assertNotIn("on_research", source)
        self.assertNotIn("on_tick", source)
        self.assertNotIn("pairs(force.technologies)", source)
        self.assertIn("on_technology_effects_reset", source)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    LegacyCannonCreditTests.lua = LuaRuntime(unpack_returned_tuples=True)
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(LegacyCannonCreditTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)
