"""Pinned-Lupa opponents for the shared test-only Lua table conversion."""
import argparse
from pathlib import Path
import sys
import unittest

from lua_table_values import from_lua, to_lua


class LuaTableValuesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)

    def test_to_lua_preserves_false_zero_and_existing_none_holes(self):
        value = {"flag": False, "zero": 0, "list": [False, None, 0], "none": None}
        table = to_lua(self.lua, value)
        self.assertIs(type(table["flag"]), bool)
        self.assertFalse(table["flag"])
        self.assertIs(type(table["zero"]), int)
        self.assertEqual(0, table["zero"])
        self.assertIsNone(table["none"])
        list_items = dict(table["list"].items())
        self.assertEqual({1: False, 3: 0}, list_items)
        self.assertIs(type(list_items[1]), bool)
        self.assertFalse(list_items[1])
        self.assertIs(type(list_items[3]), int)
        self.assertEqual(0, list_items[3])

    def test_from_lua_preserves_false_zero_dense_empty_sparse_and_mixed_shapes(self):
        dense = self.lua.eval('{false, 0, "value"}')
        sparse = self.lua.eval('{[1]="one", [3]="three"}')
        mixed = self.lua.eval('{[1]="one", label="value"}')
        decoded_dense = from_lua(self.lua, dense)
        self.assertIs(type(decoded_dense[0]), bool)
        self.assertFalse(decoded_dense[0])
        self.assertIs(type(decoded_dense[1]), int)
        self.assertEqual(0, decoded_dense[1])
        self.assertEqual([False, 0, "value"], decoded_dense)
        self.assertEqual({}, from_lua(self.lua, self.lua.eval('{}')))
        self.assertEqual({1: "one", 3: "three"}, from_lua(self.lua, sparse))
        self.assertEqual({1: "one", "label": "value"}, from_lua(self.lua, mixed))
        nested = self.lua.eval('{[1]={[2]="two"}, named={[1]="one", label="value"}}')
        self.assertEqual({1: {2: "two"}, "named": {1: "one", "label": "value"}},
                         from_lua(self.lua, nested))

    def test_from_lua_rejects_boolean_numeric_key_collision(self):
        for value in (self.lua.eval('{[false]="false", [0]="zero"}'),
                      self.lua.eval('{[true]="true", [1]="one"}')):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "keys collide"):
                    from_lua(self.lua, value)

    def test_to_lua_rejects_dict_list_and_mutual_python_cycles(self):
        dictionary = {}
        dictionary["self"] = dictionary
        sequence = []
        sequence.append(sequence)
        mutual_dictionary, mutual_sequence = {}, []
        mutual_dictionary["sequence"] = mutual_sequence
        mutual_sequence.append(mutual_dictionary)
        for value in (dictionary, sequence, mutual_dictionary):
            with self.subTest(value_type=type(value).__name__):
                with self.assertRaisesRegex(ValueError, "cyclic Python container"):
                    to_lua(self.lua, value)

    def test_from_lua_uses_rawequal_for_proxy_cycles_and_ignores_eq_metamethods(self):
        cyclic = self.lua.eval('(function() local t={}; t.self=t; return t end)()')
        with self.assertRaisesRegex(ValueError, "cyclic Lua table"):
            from_lua(self.lua, cyclic)
        left, right, aliases = self.lua.execute(r'''
          local mt = {__eq = function() error("comparison invoked") end}
          local left = setmetatable({flag=false, zero=0}, mt)
          local right = setmetatable({flag=false, zero=0}, mt)
          return left, right, {left=left, right=right, again=left}
        ''')
        with self.assertRaisesRegex(Exception, "comparison invoked"):
            self.lua.eval("function(a, b) return a == b end")(left, right)
        plain = from_lua(self.lua, aliases)
        self.assertEqual({"left": {"flag": False, "zero": 0},
                          "right": {"flag": False, "zero": 0},
                          "again": {"flag": False, "zero": 0}}, plain)
        self.assertIs(type(plain["left"]["flag"]), bool)
        self.assertIs(type(plain["left"]["zero"]), int)
        self.assertIsNot(plain["left"], plain["again"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LuaTableValuesTests))
    raise SystemExit(not result.wasSuccessful())
