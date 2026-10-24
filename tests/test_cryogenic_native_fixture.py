"""Host-stage controls for the private MIR5 cryogenic native-unit fixture.

These checks execute the fixture against a deliberately small data-stage
double. They verify fixture syntax and its own guards, never launch Factorio.
"""
import argparse
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/cryogenic-native"
PROFILE = ROOT / "tests/profiles/cryogenic-native-space-age-f210.json"


class CryogenicNativeFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().settings_updates = (FIXTURE / "settings-updates.lua").as_posix()
        self.lua.globals().data_updates = (FIXTURE / "data-updates.lua").as_posix()
        self.lua.globals().data_final_fixes = (FIXTURE / "data-final-fixes.lua").as_posix()
        self.lua.execute(r'''
          local function copy(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local out = {}
            seen[value] = out
            for key, item in pairs(value) do out[copy(key, seen)] = copy(item, seen) end
            return out
          end
          table.deepcopy = function(value) return copy(value) end

          function run_cryogenic_fixture(mutation)
            data = {raw = {
              ["string-setting"] = {
                ["mir-science-pack-ingredient-policy"] = {default_value = "configured"}
              },
              tool = {
                ["automation-science-pack"] = {
                  type = "tool", name = "automation-science-pack", durability = 1
                }
              },
              item = {},
              resource = {
                ["iron-ore"] = {type = "resource", name = "iron-ore", minable = {result = "iron-ore"}}
              },
              lab = {lab = {inputs = {"automation-science-pack", "cryogenic-science-pack"}}},
              recipe = {
                ["cryogenic-science-pack"] = {
                  name = "cryogenic-science-pack", enabled = false,
                  main_product = "cryogenic-science-pack",
                  results = {{type = "item", name = "cryogenic-science-pack", amount = 1}}
                }
              },
              technology = {
                ["cryogenic-plant"] = {name = "cryogenic-plant"},
                ["cryogenic-science-pack"] = {
                  name = "cryogenic-science-pack", prerequisites = {"cryogenic-plant"},
                  effects = {{type = "unlock-recipe", recipe = "cryogenic-science-pack"}},
                  research_trigger = {type = "craft-item", item = "cryogenic-plant"}
                },
                ["recipe-prod-fixture-1"] = {
                  enabled = true,
                  unit = {ingredients = {{"cryogenic-science-pack", 1}}},
                  prerequisites = {"cryogenic-science-pack"}
                },
                ["recipe-prod-fixture-disabled-1"] = {
                  enabled = false,
                  unit = {ingredients = {{"cryogenic-science-pack", 1}}},
                  prerequisites = {}
                }
              }
            }}
            function data:extend(rows)
              for _, prototype in ipairs(rows) do
                self.raw[prototype.type] = self.raw[prototype.type] or {}
                self.raw[prototype.type][prototype.name] = prototype
              end
            end
            log = function() end

            assert(loadfile(settings_updates))()
            assert(loadfile(data_updates))()

            local generated = data.raw.technology["recipe-prod-fixture-1"]
            if mutation == "missing-gate" then generated.prerequisites = {} end
            if mutation == "changed-quantity" then generated.unit.ingredients[1][2] = 2 end

            local chunk = assert(loadfile(data_final_fixes))
            local ok, message = pcall(chunk)
            return ok, message, {
              policy = data.raw["string-setting"]["mir-science-pack-ingredient-policy"].default_value,
              foreign_pack = data.raw.tool["mir5-cryogenic-native-science"],
              resource = data.raw.resource["mir5-cryogenic-native-science-resource"],
              lab_input = data.raw.lab.lab.inputs[3],
              owner = data.raw.technology["cryogenic-science-pack"]
            }
          end
        ''')

    def run_fixture(self, mutation="pass"):
        return self.lua.eval("run_cryogenic_fixture")(mutation)

    def test_fixture_recreates_the_bounded_foreign_native_unit_shape(self):
        ok, message, state = self.run_fixture()
        self.assertTrue(ok, message)
        self.assertEqual(state["policy"], "all-official")
        self.assertEqual(state["foreign_pack"]["name"], "mir5-cryogenic-native-science")
        self.assertEqual(state["resource"]["minable"]["result"], "mir5-cryogenic-native-science")
        self.assertEqual(state["lab_input"], "mir5-cryogenic-native-science")
        owner = state["owner"]
        self.assertIsNone(owner["research_trigger"])
        self.assertEqual(owner["unit"]["ingredients"][1][1], "mir5-cryogenic-native-science")

    def test_final_guard_rejects_a_lost_native_gate_or_changed_quantity(self):
        for mutation, expected in (
            ("missing-gate", "exact native cryogenic gate was lost"),
            ("changed-quantity", "cryogenic science quantity changed"),
        ):
            with self.subTest(mutation=mutation):
                ok, message, _ = self.run_fixture(mutation)
                self.assertFalse(ok)
                self.assertIn(expected, str(message))

    def test_profile_is_an_exact_space_age_capture_input(self):
        profile = json.loads(PROFILE.read_text(encoding="utf-8"))
        self.assertEqual(profile, {"mods": [
            {"name": "base", "version": "2.1.23", "enabled": True},
            {"name": "elevated-rails", "version": "2.1.23", "enabled": True},
            {"name": "quality", "version": "2.1.23", "enabled": True},
            {"name": "recycler", "version": "2.1.23", "enabled": True},
            {"name": "space-age", "version": "2.1.23", "enabled": True},
            {"name": "mir-fixture-mir5-cryogenic-native", "version": "0.1.0", "enabled": True},
        ]})
        self.assertNotIn("more-infinite-research", {row["name"] for row in profile["mods"]})

    def test_fixture_declares_only_the_private_mir5_dependency_and_no_mir4_import(self):
        info = json.loads((FIXTURE / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["name"], "mir-fixture-mir5-cryogenic-native")
        self.assertIn("more-infinite-research = 5.0.21000", info["dependencies"])
        for source in FIXTURE.glob("*.lua"):
            self.assertNotIn("__more-infinite-research__", source.read_text(encoding="utf-8"))
            self.assertNotIn("mir472", source.read_text(encoding="utf-8"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CryogenicNativeFixtureTests))
    sys.exit(0 if result.wasSuccessful() else 1)
