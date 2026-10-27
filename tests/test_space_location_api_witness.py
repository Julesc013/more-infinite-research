"""Host controls for the private Factorio2.1 space-location API witness.

The doubles below check only the fixture's bounded protocol.  The native
scenario remains required to observe Factorio's real LuaForce return values
and LuaCustomTable shapes.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/space-location-api-witness"
PROFILE = ROOT / "tests/profiles/space-location-api-witness-f210-2123.json"


class SpaceLocationApiWitnessTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().control_path = (FIXTURE / "control.lua").as_posix()
        self.lua.execute(r'''
          function run_space_location_witness(mutation)
            local callbacks, reports, saves = {}, {}, {}
            local primary_locations = {vulcanus = false, gleba = false}
            local function technology(name, researched, effects)
              return {
                name = name, valid = true, researched = researched,
                prototype = {object_name = "LuaTechnologyPrototype", effects = effects}
              }
            end
            local effects = {
              object_name = "LuaCustomTable",
              {type = "unlock-space-location", space_location = "vulcanus"},
              {type = "unlock-travel-to-space-platforms", modifier = true}
            }
            if mutation == "wrong-effect" then effects[1].space_location = "gleba" end
            local primary_techs = {
              object_name = "LuaCustomTable",
              ["planet-discovery-vulcanus"] = technology("planet-discovery-vulcanus", false, effects),
              ["planet-discovery-gleba"] = technology("planet-discovery-gleba", false, {})
            }
            local function primary_force()
              return {
                name = "player", valid = true, technologies = primary_techs,
                lock_space_location = function(name) primary_locations[name] = false end,
                unlock_space_location = function(name) primary_locations[name] = true end,
                is_space_location_unlocked = function(name) return primary_locations[name] == true end
              }
            end
            local primary = primary_force()
            local sentinel = nil
            game = {
              forces = {player = primary},
              create_force = function(name)
                sentinel = {
                  name = name, valid = true,
                  technologies = {object_name = "LuaCustomTable", automation = technology("automation", false, {})},
                  enable_all_prototypes = function() end,
                  research_queue_enabled = false, current_research = nil
                }
                setmetatable(sentinel, {
                  __newindex = function(t, key, value)
                    rawset(t, key, value)
                    if key == "research_queue" then rawset(t, "current_research", value[1]) end
                  end
                })
                game.forces[name] = sentinel
                return sentinel
              end,
              server_save = function(name) saves[#saves + 1] = name end
            }
            storage = {}
            helpers = {table_to_json = function(row) reports[#reports + 1] = row; return "fixture-json" end}
            log = function() end
            script = {
              on_init = function(callback) callbacks.init = callback end,
              on_load = function(callback) callbacks.load = callback end,
              on_event = function(_, callback) callbacks.tick = callback end
            }
            defines = {events = {on_tick = 1}}
            assert(loadfile(control_path))()
            local ok, message = pcall(callbacks.init)
            if not ok then return false, tostring(message), reports, saves end
            local initial = reports[1]
            if mutation == "queue-drift" then
              sentinel.research_queue = {}
              sentinel.current_research = nil
            end
            callbacks.load()
            ok, message = pcall(callbacks.tick)
            return ok, tostring(message), reports, saves
          end
        ''')

    def run_fixture(self, mutation="pass"):
        return self.lua.eval("run_space_location_witness")(mutation)

    def test_fixture_emits_initial_and_pure_reload_witnesses(self):
        ok, message, reports, saves = self.run_fixture()
        self.assertTrue(ok, message)
        self.assertEqual(saves[1], "mir5-native-complete")
        self.assertEqual((reports[1]["stage"], reports[2]["stage"]), ("initial", "reload"))
        witnesses = reports[1]["witnesses"]
        self.assertTrue(witnesses["fixture_owned_lock_then_unlock"])
        self.assertFalse(witnesses["locked_after_lock"])
        self.assertTrue(witnesses["unlocked_after_unlock"])
        self.assertTrue(witnesses["duplicate_unlock_unchanged"])
        self.assertFalse(witnesses["unresearched_location_unlocked"])
        self.assertEqual(witnesses["effect"]["force_technologies_object_name"], "LuaCustomTable")
        self.assertEqual(witnesses["effect"]["effects_object_name"], "LuaCustomTable")
        self.assertEqual(witnesses["effect"]["effect_space_location"], "vulcanus")
        self.assertFalse(witnesses["researched_earned"])

    def test_fixture_rejects_a_different_effect_location_or_queue_drift(self):
        for mutation, expected in (
            ("wrong-effect", "space-location technology unlock effect differs"),
            ("queue-drift", "unrelated sentinel force or queue changed"),
        ):
            with self.subTest(mutation=mutation):
                ok, message, _, _ = self.run_fixture(mutation)
                self.assertFalse(ok)
                self.assertIn(expected, message)

    def test_profile_and_fixture_have_the_exact_standalone_space_age_closure(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile["kind"], "mir5-space-location-api-witness-f210-native-selection")
        self.assertEqual(profile["target"], "f210-standalone")
        self.assertEqual(profile["engine"], {
            "version": "2.1.23",
            "sha256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
        })
        self.assertEqual([(row["name"], row["version"], row["enabled"]) for row in profile["mods"]], [
            ("base", "2.1.23", True), ("elevated-rails", "2.1.23", True),
            ("quality", "2.1.23", True), ("recycler", "2.1.23", True),
            ("space-age", "2.1.23", True), ("more-infinite-research", "5.0.21000", True),
            ("mir-fixture-mir5-space-location-api-witness", "0.1.0", True),
        ])
        self.assertEqual(profile["archive_sha256"], {
            "more-infinite-research_5.0.21000.zip": "7CE6A4DF78019F6B98237E638A1C927C5FDB538D4A1442EE22D846DD962DDCDC",
            "mir-fixture-mir5-space-location-api-witness_0.1.0.zip": "512760CDB3FA9CA75370CF1A1C223F386291BEDDFFAFF6E7CC333E40A8C6BAD1",
        })
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["name"], "mir-fixture-mir5-space-location-api-witness")
        self.assertEqual(info["factorio_version"], "2.1")
        self.assertEqual(info["dependencies"], [
            "base >= 2.1.23", "space-age = 2.1.23", "more-infinite-research = 5.0.21000"
        ])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(SpaceLocationApiWitnessTests))
    sys.exit(0 if result.wasSuccessful() else 1)
