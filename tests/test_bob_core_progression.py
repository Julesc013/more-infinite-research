"""Exact F210 Bob Core science/progression controls from an independent capture."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
FACTS_PATH = ROOT / "tests/fixtures/bob-core-f210-progression-captured-facts.json"


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, item in value.items():
            table[key] = _lua_value(lua, item)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, item in enumerate(value, 1):
            table[index] = _lua_value(lua, item)
        return table
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(item) for key, item in items.items()}


class BobCoreProgressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        reference = cls.facts["independent_reference"]
        if reference["candidate_output_used"] or reference["release_qualification"]:
            raise AssertionError("Bob Core progression facts must remain independent source evidence")
        if reference["native_run"] != {"id": 40069301778, "artifact_id": 12550447321, "members_verified": 26}:
            raise AssertionError("Bob Core progression facts lost their verified capture identity")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = (ROOT / "source").as_posix()
        self.lua.execute('''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits = "independent_probability", true
          target.productivity_ignores_stats = true
        ''')
        self.catalogue = self.lua.execute('return require("compatibility.modern_catalogue")')
        self.modern = self.lua.execute('return require("research.modern")')

    def active_mods(self):
        return _lua_value(self.lua, self.facts["required_mods"])

    def raw_fixture(self):
        science = self.facts["advanced_logistic_science"]
        return _lua_value(self.lua, {
            "item": {science["name"]: {}},
            "recipe": {
                science["name"]: {
                    "enabled": science["recipe"]["enabled"],
                    "allow_productivity": science["recipe"]["allow_productivity"],
                    "results": deepcopy(science["recipe"]["results"]),
                },
                "capture-robot-rocket": {},
                "ice-platform": {},
                "space-platform-foundation": {},
            },
            "technology": {
                science["owner"]["name"]: {
                    "effects": [{"type": "unlock-recipe", "recipe": science["owner"]["unlock_recipe"]}],
                },
            },
        })

    def selection(self):
        return self.catalogue["select"](self.active_mods())

    def test_exact_captured_vectors_effect_and_icon_are_profile_local_and_detached(self):
        selection = _plain(self.selection())
        self.assertEqual("bob-core-f210", selection["profile"])
        self.assertTrue(selection["bob_core"])
        self.assertTrue(selection["bob_core_progression"])

        continuations = {row["key"]: row for row in selection["continuations"]}
        self.assertEqual(self.facts["continuations"], {
            key: _plain(self.catalogue["science_names"](continuations[key]["science"]))
            for key in self.facts["continuations"]
        })

        definitions = {row["key"]: row for row in selection["definitions"]}
        science_pack = definitions["research_science_pack_productivity"]
        self.assertEqual(self.facts["science_pack_productivity"]["science"],
                         _plain(self.catalogue["science_names"](science_pack["science"])))
        self.assertEqual(self.facts["science_pack_productivity"]["effects"],
                         [effect["recipe"] for effect in science_pack["effects"]])
        self.assertEqual(self.facts["advanced_circuit_icon"], {
            "icon": definitions["research_advanced_circuit"]["icon"],
            "icon_size": definitions["research_advanced_circuit"]["icon_size"],
        })

        selected_continuations = [continuations[key] for key in self.facts["continuations"]]
        streams = {science_pack["family"]: deepcopy(science_pack["tuning"])}
        for row in selected_continuations:
            streams[row["family"]] = deepcopy(row["defaults"])
        built = _plain(self.modern["technologies"](_lua_value(self.lua, {
            "definitions": [science_pack], "continuations": selected_continuations, "k2_imersite": False,
        }), _lua_value(self.lua, {"streams": streams})))
        by_id = {row["name"]: row for row in built}
        self.assertEqual(self.facts["science_pack_productivity"]["science"],
                         [row[0] for row in by_id["recipe-prod-research_science_pack_productivity-1"]["unit"]["ingredients"]])
        self.assertEqual(self.facts["science_pack_productivity"]["effects"],
                         [row["recipe"] for row in by_id["recipe-prod-research_science_pack_productivity-1"]["effects"]])
        for key, science in self.facts["continuations"].items():
            technology = by_id[continuations[key]["id"]]
            self.assertEqual(science, [row[0] for row in technology["unit"]["ingredients"]])
            self.assertTrue(all(name in technology["prerequisites"] for name in science))

        science_pack["effects"][1]["recipe"] = "corrupted"
        repeated = {row["key"]: row for row in _plain(self.selection())["definitions"]}
        self.assertNotEqual("corrupted", repeated["research_science_pack_productivity"]["effects"][0]["recipe"])

        without_bob = _plain(self.catalogue["select"](_lua_value(self.lua, {"space-age": "2.1.23"})))
        ordinary = {row["key"]: row for row in without_bob["definitions"]}
        self.assertFalse(without_bob["bob_core"])
        self.assertFalse(without_bob["bob_core_progression"])
        self.assertNotIn(self.facts["advanced_logistic_science"]["name"],
                         [effect["recipe"] for effect in ordinary["research_science_pack_productivity"]["effects"]])

    def test_named_science_preflight_is_read_only_and_rejects_each_required_boundary(self):
        selection = self.selection()
        raw = self.raw_fixture()
        before = _plain(raw)
        self.modern["preflight_recipe_patches"](selection, raw)
        self.assertEqual(before, _plain(raw))

        missing_item = self.raw_fixture()
        missing_item["item"][self.facts["advanced_logistic_science"]["name"]] = None
        missing_item_before = _plain(missing_item)
        with self.assertRaisesRegex(Exception, "missing named science pack"):
            self.modern["preflight_recipe_patches"](selection, missing_item)
        self.assertEqual(missing_item_before, _plain(missing_item))

        missing_recipe = self.raw_fixture()
        missing_recipe["recipe"][self.facts["advanced_logistic_science"]["name"]] = None
        missing_recipe_before = _plain(missing_recipe)
        with self.assertRaisesRegex(Exception, "named science recipe changed"):
            self.modern["preflight_recipe_patches"](selection, missing_recipe)
        self.assertEqual(missing_recipe_before, _plain(missing_recipe))

        wrong_owner = self.raw_fixture()
        wrong_owner["technology"][self.facts["advanced_logistic_science"]["name"]]["effects"][1]["recipe"] = "changed-unlock"
        wrong_owner_before = _plain(wrong_owner)
        with self.assertRaisesRegex(Exception, "named science owner changed"):
            self.modern["preflight_recipe_patches"](selection, wrong_owner)
        self.assertEqual(wrong_owner_before, _plain(wrong_owner))

        wrong_type = self.raw_fixture()
        wrong_type["recipe"][self.facts["advanced_logistic_science"]["name"]]["results"][1]["type"] = "fluid"
        with self.assertRaisesRegex(Exception, "named science recipe changed"):
            self.modern["preflight_recipe_patches"](selection, wrong_type)

        nonpositive = self.raw_fixture()
        nonpositive["recipe"][self.facts["advanced_logistic_science"]["name"]]["results"][1]["amount"] = 0
        with self.assertRaisesRegex(Exception, "named science recipe changed"):
            self.modern["preflight_recipe_patches"](selection, nonpositive)

        duplicate_unlock = self.raw_fixture()
        duplicate_unlock["technology"][self.facts["advanced_logistic_science"]["name"]]["effects"][2] = _lua_value(self.lua, {
            "type": "unlock-recipe", "recipe": self.facts["advanced_logistic_science"]["name"],
        })
        with self.assertRaisesRegex(Exception, "named science owner changed"):
            self.modern["preflight_recipe_patches"](selection, duplicate_unlock)

        changed_yield = self.raw_fixture()
        changed_yield["recipe"][self.facts["advanced_logistic_science"]["name"]]["results"][1]["amount"] = 4
        changed_yield["recipe"][self.facts["advanced_logistic_science"]["name"]]["results"][1]["probability"] = 0.5
        self.modern["preflight_recipe_patches"](selection, changed_yield)

        invalid_probability = self.raw_fixture()
        invalid_probability["recipe"][self.facts["advanced_logistic_science"]["name"]]["results"][1]["probability"] = 1.1
        with self.assertRaisesRegex(Exception, "named science recipe changed"):
            self.modern["preflight_recipe_patches"](selection, invalid_probability)

        unrelated_owner_effect = self.raw_fixture()
        unrelated_owner_effect["technology"][self.facts["advanced_logistic_science"]["name"]]["effects"][2] = _lua_value(self.lua, {
            "type": "unlock-recipe", "recipe": "unrelated-recipe",
        })
        self.modern["preflight_recipe_patches"](selection, unrelated_owner_effect)

    def test_data_stage_aborts_before_any_mir_write_for_each_named_boundary(self):
        pack = self.facts["advanced_logistic_science"]["name"]

        cases = []
        missing_item = _plain(self.raw_fixture())
        missing_item["item"].pop(pack)
        cases.append(("missing named science pack", missing_item))

        missing_recipe = _plain(self.raw_fixture())
        missing_recipe["recipe"].pop(pack)
        cases.append(("named science recipe changed", missing_recipe))

        missing_owner = _plain(self.raw_fixture())
        missing_owner["technology"].pop(pack)
        cases.append(("named science owner changed", missing_owner))

        changed_unlock = _plain(self.raw_fixture())
        changed_unlock["technology"][pack]["effects"][0]["recipe"] = "changed-unlock"
        cases.append(("named science owner changed", changed_unlock))

        wrong_type = _plain(self.raw_fixture())
        wrong_type["recipe"][pack]["results"][0]["type"] = "fluid"
        cases.append(("named science recipe changed", wrong_type))

        nonpositive = _plain(self.raw_fixture())
        nonpositive["recipe"][pack]["results"][0]["amount"] = 0
        cases.append(("named science recipe changed", nonpositive))

        duplicate_unlock = _plain(self.raw_fixture())
        duplicate_unlock["technology"][pack]["effects"].append({"type": "unlock-recipe", "recipe": pack})
        cases.append(("named science owner changed", duplicate_unlock))

        for expected, raw in cases:
            with self.subTest(expected=expected):
                self.assert_data_stage_rejects_before_write(raw, expected)

    def assert_data_stage_rejects_before_write(self, raw, expected):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = (ROOT / "source").as_posix()
        lua.globals().mods = _lua_value(lua, self.facts["required_mods"])
        lua.globals().fixture_raw = _lua_value(lua, raw)
        lua.globals().expected_error = expected
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits = "independent_probability", true
          target.productivity_ignores_stats = true
          data = {raw=fixture_raw, writes=0}
          settings, helpers, log = {startup={}}, {}, function() end
          package.preload["research.settings"] = function()
            return {resolve=function() return {enabled=false, options={}} end}
          end
          package.preload["research.productivity"] = function()
            return {gears=function() return {type="technology", name="fixture-gears"} end}
          end
          package.preload["research.generator"] = function()
            return {install=function(_, stage) stage.writes = stage.writes + 1 end}
          end
          local ok, message = pcall(require, "data-final-fixes")
          assert(not ok and tostring(message):find(expected_error, 1, true), tostring(message))
          assert(data.writes == 0, "MIR wrote before Bob Core preflight rejection: " .. expected_error)
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobCoreProgressionTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
