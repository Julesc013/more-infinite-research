"""Host checks for the private F200 Base/Space Age ATAN gameplay fixture.

These validate fixture admission and its exact accelerated research identities.
They do not simulate a Factorio lab, queue, effect accounting, or save reload.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/atan-gameplay"
PROFILES = {
    "base": ROOT / "tests/profiles/atan-gameplay-base-f200-2077.json",
    "space-age": ROOT / "tests/profiles/atan-gameplay-space-age-f200-2077.json",
}
AIR = "recipe-prod-research_air_scrubbing_clean_filter-1"
ASH = "recipe-prod-research_ash_separation-1"


def lua_table(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, nested in value.items():
            table[key] = lua_table(lua, nested)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, nested in enumerate(value, start=1):
            table[index] = lua_table(lua, nested)
        return table
    return value


def raw_fixture(space_age=False):
    return {
        "technology": {
            AIR: {
                "name": AIR, "max_level": "infinite",
                "effects": [
                    {"type": "change-recipe-productivity", "recipe": "atan-pollution-filter", "change": 0.05},
                    *([{ "type": "change-recipe-productivity", "recipe": "atan-spore-filter", "change": 0.05}]
                      if space_age else []),
                ],
                "unit": {"count_formula": "8000*2^(L-1)", "time": 60},
            },
            ASH: {
                "name": ASH, "max_level": "infinite",
                "effects": [{"type": "change-recipe-productivity", "recipe": "atan-ash-seperation", "change": 0.05}],
                "unit": {"count_formula": "8000*2^(L-1)", "time": 90},
            },
        },
        "recipe": {"foreign-route": {"name": "foreign-route", "enabled": False}},
    }


class AtanGameplayFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().fixture_path = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          function run_atan_fixture(raw_value, mods_value)
            data = {raw = raw_value}
            mods = mods_value
            local ok, message = pcall(function() assert(loadfile(fixture_path))() end)
            return ok, message, data.raw
          end
        ''')

    def run_fixture(self, variant="base", mutate=None):
        space_age = variant == "space-age"
        raw = raw_fixture(space_age)
        if mutate is not None:
            mutate(raw)
        mods = {
            "base": "2.0.77", "atan-air-scrubbing": "0.2.8", "atan-ash": "2.2.1",
            "more-infinite-research": "5.0.20000",
        }
        if space_age:
            mods.update({"space-age": "2.0.77", "elevated-rails": "2.0.77", "quality": "2.0.77"})
        return self.lua.eval("run_atan_fixture")(lua_table(self.lua, raw), lua_table(self.lua, mods))

    def test_acceleration_preserves_the_exact_base_and_space_age_effect_vectors(self):
        for variant, expected_air in (("base", ["atan-pollution-filter"]),
                                      ("space-age", ["atan-pollution-filter", "atan-spore-filter"])):
            with self.subTest(variant=variant):
                ok, message, raw = self.run_fixture(variant)
                self.assertTrue(ok, message)
                self.assertEqual("1", raw["technology"][AIR]["unit"]["count_formula"])
                self.assertEqual(1, raw["technology"][AIR]["unit"]["time"])
                self.assertEqual("1", raw["technology"][ASH]["unit"]["count_formula"])
                self.assertEqual(1, raw["technology"][ASH]["unit"]["time"])
                air_effects = raw["technology"][AIR]["effects"]
                self.assertEqual(expected_air, [air_effects[index]["recipe"] for index in range(1, len(air_effects) + 1)])
                self.assertEqual("atan-ash-seperation", raw["technology"][ASH]["effects"][1]["recipe"])
                self.assertEqual("foreign-route", raw["recipe"]["foreign-route"]["name"])

    def test_guard_rejects_wrong_workload_or_shared_owner_effect_vector(self):
        cases = (
            ("base", lambda raw: raw["technology"][AIR].update({"enabled": False}), "workload changed"),
            ("base", lambda raw: raw["technology"][AIR]["unit"].update({"time": 61}), "workload changed"),
            ("base", lambda raw: raw["technology"][AIR]["effects"].append(
                {"type": "change-recipe-productivity", "recipe": "atan-spore-filter", "change": 0.05}), "effect vector changed"),
            ("space-age", lambda raw: raw["technology"][AIR]["effects"].pop(), "effect vector changed"),
            ("space-age", lambda raw: raw["technology"][ASH]["effects"].__setitem__(0,
                {"type": "change-recipe-productivity", "recipe": "atan-ash-seperation", "change": 0.1}), "effect changed"),
        )
        for variant, mutate, expected in cases:
            with self.subTest(variant=variant, expected=expected):
                ok, message, _ = self.run_fixture(variant, mutate)
                self.assertFalse(ok)
                self.assertIn(expected, str(message))

    def test_captured_missing_enabled_and_explicit_true_share_native_default(self):
        facts = json.loads((ROOT / "tests/fixtures/atan-f200-captured-facts.json").read_text(encoding="utf-8"))
        self.assertTrue(all("enabled" not in row for row in facts["published_rows"]))
        ok, message, _ = self.run_fixture(mutate=lambda raw: raw["technology"][AIR].update({"enabled": True}))
        self.assertTrue(ok, message)

    def test_profiles_are_exact_f200_closures_and_fixture_dependencies_are_private(self):
        base = json.loads(PROFILES["base"].read_text(encoding="utf-8"))
        space_age = json.loads(PROFILES["space-age"].read_text(encoding="utf-8"))
        expected_hashes = {
            "atan-air-scrubbing_0.2.8.zip": "FC1425EBEA1B2BD5BDD6DADB7BD594423DEBE8180D4781B25C92EA593D5D9AEF",
            "atan-ash_2.2.1.zip": "B46B85FC39D16331EA031F5F6459C5E99E8011097E782F958C08CE8AC9EEAE6C",
            "mir-fixture-mir5-active-mods-observer_0.1.0.zip": "723D1E7721449FC26040E5E6629416767BDC20AD79CF8723115846DB662A1F87",
        }
        for name, profile, expected_mods in (
            ("base", base, ["base", "atan-air-scrubbing", "atan-ash", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", "mir-fixture-mir5-atan-gameplay"]),
            ("space-age", space_age, ["base", "elevated-rails", "quality", "space-age", "atan-air-scrubbing", "atan-ash", "mir-fixture-mir5-active-mods-observer", "more-infinite-research", "mir-fixture-mir5-atan-gameplay"]),
        ):
            with self.subTest(profile=name):
                self.assertEqual("f200", profile["target"])
                self.assertEqual("2.0.77", profile["engine"]["version"])
                self.assertEqual(expected_mods, [row["name"] for row in profile["mods"]])
                self.assertTrue(all(row["enabled"] is True for row in profile["mods"]))
                self.assertEqual(expected_hashes, profile["archive_sha256"])

        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual("mir-fixture-mir5-atan-gameplay", info["name"])
        self.assertEqual("0.1.0", info["version"])
        self.assertEqual("2.0", info["factorio_version"])
        self.assertIn("more-infinite-research = 5.0.20000", info["dependencies"])
        self.assertIn("? space-age = 2.0.77", info["dependencies"])
        for source in FIXTURE.glob("*.lua"):
            self.assertNotIn("__more-infinite-research__", source.read_text(encoding="utf-8"))

    def test_control_keeps_native_claim_boundaries_and_cold_reload_protocol_explicit(self):
        control = (FIXTURE / "control.lua").read_text(encoding="utf-8")
        self.assertIn('local SAVE = "mir5-native-complete"', control)
        self.assertIn('local AIR = "recipe-prod-research_air_scrubbing_clean_filter-1"', control)
        self.assertIn('local ASH = "recipe-prod-research_ash_separation-1"', control)
        self.assertIn('player.add_research(air)', control)
        self.assertIn('player.add_research(ash)', control)
        self.assertIn('player.add_research(probe)', control)
        self.assertIn('game.server_save(SAVE)', control)
        self.assertIn('script.on_load(function()', control)
        self.assertIn('marker("reload"', control)
        self.assertNotIn("productivity_bonus =", control)
        self.assertNotIn("reset_technology_effects", control)

    def test_ash_event_defers_probe_queue_observation_until_after_factorio_advances_it(self):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          function exercise_ash_event()
            local callbacks = {events={}}
            script = {
              active_mods = {},
              on_init = function() end,
              on_load = function() end,
              on_event = function(event, callback) callbacks.events[event] = callback end,
            }
            defines = {events={on_research_finished=1, on_tick=2}, inventory={lab_input=1}}
            storage = {}
            local player = {}
            game = {forces={player=player}}
            local lab = {
              valid=true, active=true, energy=100,
              get_inventory=function() return {clear=function() end} end,
            }
            local state = {phase="await-ash-lab", lab=lab, actual_lab_completions=1}
            storage["mir5_atan_gameplay"] = state
            assert(loadfile(control_path))()
            callbacks.events[defines.events.on_research_finished]({research={force=player, name="recipe-prod-research_ash_separation-1"}})
            return state.phase, state.actual_lab_completions, state.queue, lab.active, lab.energy
          end
        ''')
        phase, completions, queue, active, energy = self.lua.eval("exercise_ash_event")()
        self.assertEqual("await-completed-observation", phase)
        self.assertEqual(2, completions)
        self.assertIsNone(queue, "the finished ash technology must not be accepted as the pending probe")
        self.assertFalse(active)
        self.assertEqual(0, energy)


    def test_probe_observation_uses_native_queue_including_current_research(self):
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          local callbacks = {}
          script = {on_init=function() end, on_load=function() end,
            on_event=function(id, callback) callbacks[id] = callback end}
          defines = {events={on_research_finished=1, on_tick=2}, inventory={lab_input=1}}
          assert(loadfile(control_path))()
          local function upvalue(callback, wanted)
            for index=1, 30 do
              local name, value = debug.getupvalue(callback, index)
              if name == wanted then return value end
              if name == nil then break end
            end
            error("missing bounded fixture closure " .. wanted)
          end
          local completed = upvalue(callbacks[2], "assert_completed")
          local check = upvalue(completed, "assert_probe_queue")
          local probe = {name="braking-force-1"}
          local force = {current_research=probe, research_queue={probe}, research_progress=.42}
          assert(pcall(check, force, {progress=.42}, "native current entry"))
          force.research_queue = {}
          assert(not pcall(check, force, {progress=.42}, "missing current entry"))
          force.research_queue = {{name="unexpected-research"}}
          assert(not pcall(check, force, {progress=.42}, "wrong current entry"))
          force.research_queue = {probe}
          assert(not pcall(check, force, {progress=.27}, "changed research work"))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AtanGameplayFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
