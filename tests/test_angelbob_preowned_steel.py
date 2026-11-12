"""Controlled foreign-owner witness checks; no native or reporter-pack claim."""
import argparse
from copy import deepcopy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
BODY = (ROOT / "tests/fixtures/angelbob-preowned-steel/data-updates.lua").read_text()


def table(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key: table(lua, item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([table(lua, item) for item in value])
    return value


def plain(value):
    if not hasattr(value, "items"):
        return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) for key in keys):
        return [plain(value[index]) for index in range(1, len(keys) + 1)]
    return {key: plain(item) for key, item in value.items()}


class PreownedSteelWitnessTests(unittest.TestCase):
    def run_witness(self, opponent=None):
        lua = LuaRuntime(unpack_returned_tuples=True)
        self.assertEqual((5, 2), tuple(lua.lua_version))
        owner = {"name": "steel-plate-productivity", "unit": {"count_formula": "1.5^L*1000", "time": 60},
                 "foreign": {"preserved": True}, "effects": [
                     {"type": "change-recipe-productivity", "recipe": "steel-plate", "change": .1},
                     {"type": "change-recipe-productivity", "recipe": "casting-steel", "change": .1}]}
        raw = {"technology": {owner["name"]: owner}, "recipe": {
            "angels-plate-steel": {"name": "angels-plate-steel", "foreign": 42},
            "angels-plate-steel-2": {"name": "angels-plate-steel-2", "foreign": 43}}}
        if opponent == "preowned":
            owner["effects"].append({"type": "change-recipe-productivity", "recipe": "angels-plate-steel", "change": .1})
        elif opponent == "wrong-original":
            owner["effects"][1]["change"] = .2
        elif opponent == "missing-recipe":
            del raw["recipe"]["angels-plate-steel-2"]
        before = deepcopy(raw)
        lua.globals().data = table(lua, {"raw": raw})
        lua.globals().mods = table(lua, {"base": "2.1.23", "angelbob-spaceage-rebalance": "1.3.2"})
        lua.globals().log = lambda message: None
        ok, message = lua.eval("function(body) local ok, err = pcall(assert(load(body))); return ok, tostring(err) end")(BODY)
        return ok, message, before, plain(lua.globals().data.raw)

    def test_adds_only_two_missing_native_effects(self):
        ok, _, before, after = self.run_witness()
        self.assertTrue(ok)
        expected = deepcopy(before)
        expected["technology"]["steel-plate-productivity"]["effects"].extend([
            {"type": "change-recipe-productivity", "recipe": name, "change": .1}
            for name in ("angels-plate-steel", "angels-plate-steel-2")])
        self.assertEqual(expected, after)

    def test_refuses_preowned_input_without_mutation(self):
        ok, message, before, after = self.run_witness("preowned")
        self.assertFalse(ok)
        self.assertIn("requires unextended", message)
        self.assertEqual(before, after)

    def test_refuses_wrong_original_scalar_without_mutation(self):
        ok, message, before, after = self.run_witness("wrong-original")
        self.assertFalse(ok)
        self.assertIn("scalar differs", message)
        self.assertEqual(before, after)

    def test_preflights_both_recipes_before_mutating(self):
        ok, message, before, after = self.run_witness("missing-recipe")
        self.assertFalse(ok)
        self.assertIn("recipe is absent", message)
        self.assertEqual(before, after)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PreownedSteelWitnessTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)
