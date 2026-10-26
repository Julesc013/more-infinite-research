"""Independent q005/q006 F210 full-Bob sulfur and acid target controls."""

import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source"
CONTEXT_PATH = ROOT / "tests/fixtures/bob-productivity-f210-upstream-context.json"
F210_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"


def _plain(value):
    if not hasattr(value, "items"):
        return value
    items = dict(value.items())
    if items and set(items) == set(range(1, len(items) + 1)):
        return [_plain(items[index]) for index in range(1, len(items) + 1)]
    return {key: _plain(nested) for key, nested in items.items()}


def _lua_value(lua, value):
    if isinstance(value, dict):
        table = lua.table()
        for key, nested in value.items():
            table[key] = _lua_value(lua, nested)
        return table
    if isinstance(value, list):
        table = lua.table()
        for index, nested in enumerate(value, start=1):
            table[index] = _lua_value(lua, nested)
        return table
    return value


class BobProductivityF210PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context = json.loads(CONTEXT_PATH.read_text(encoding="utf-8"))
        if cls.context.get("schema") != "MIR5BobProductivityF210UpstreamContextV1":
            raise AssertionError("Bob productivity context schema changed")

    def lua(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = SOURCE_ROOT.as_posix()
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f210", "2.1", "2.1.23"
          target.distribution_version, target.cargo_research = "5.0.21000", true
          target.recipe_probability, target.receiver_limits, target.productivity_ignores_stats = "independent_probability", true, true
        ''')
        return lua

    def case(self, name):
        return self.context["cases"][name]

    def _module(self, lua):
        return lua.execute('return require("compatibility.bob_productivity")')

    def _select(self, lua, active):
        return self._module(lua)["select"](_lua_value(lua, active))

    def _preflight(self, lua, name, raw=None, active=None):
        case = self.case(name)
        raw = deepcopy(raw if raw is not None else case["raw"])
        active = deepcopy(active if active is not None else case["selection"])
        return self._module(lua)["preflight"](_lua_value(lua, raw), _lua_value(lua, active))

    def _rebuild(self, name, percent):
        lua = self.lua()
        case = self.case(name)
        module = self._module(lua)
        raw = deepcopy(case["raw"])
        active = deepcopy(case["selection"])
        profile = module["preflight"](_lua_value(lua, raw), _lua_value(lua, active))
        self.assertEqual("space-age" if name == "space_age" else "base", profile)
        flags = _plain(module["replacement_product_target_families"](_lua_value(lua, active)))
        expected = case["published_rows"]
        rows = []
        for technology_name, published in expected.items():
            family = technology_name.removeprefix("recipe-prod-").removesuffix("-1")
            seed = "sulfur" if family == "research_sulfur" else "sulfuric-acid"
            rows.append({
                "name": technology_name,
                "unit": deepcopy(published["unit"]),
                "prerequisites": deepcopy(published["prerequisites"]),
                "effects": [{"type": "change-recipe-productivity", "recipe": seed, "change": percent}],
            })
        values = {"streams": {
            "research_sulfur": {"effect_percent": percent * 100},
            "research_sulfuric_acid_productivity": {"effect_percent": percent * 100},
        }}
        extension = lua.execute('return require("research.product_target_extension")')
        rows_lua = _lua_value(lua, rows)
        extension["extend"](rows_lua, _lua_value(lua, values), _lua_value(lua, {
            "raw": raw,
            "mods": active,
            "replacement_product_target_families": flags,
        }))
        return _plain(rows_lua), expected, flags

    def test_context_binds_independent_q005_q006_inputs_and_b6_oracle(self):
        self.assertEqual(F210_SHA256, self.context["scope"]["engine"]["sha256"])
        self.assertFalse(self.context["scope"]["claims"]["candidate_raw_used"])
        self.assertEqual("BE2D0EEA2DE65CF32218107EB1DB679BF0B826599C89C4E2892F60B234405F5F",
                         self.context["provider_fact"]["archive"]["sha256"])
        expected_hashes = {
            "base": ("E50A66C38427AE45765564D301085BF42BC17FB904BAF93EB296C4CF4B648D6F",
                     "80462037B1982AF008B845D1389045C69E8D0BF58C0D7BC7A287BD4B4FC4024F"),
            "space_age": ("9850830424454DE5760C3CE0DB2A6D0055875339DE40B80EC08433E288EAFE2A",
                          "0419DF1FD2C5495B5BEC692268F30294F1E19C168D199CB9BF4C7569EF20E6A4"),
        }
        for name, (upstream, published) in expected_hashes.items():
            with self.subTest(name=name):
                capture = self.case(name)["capture"]
                self.assertEqual(upstream, capture["upstream_raw_sha256"])
                self.assertEqual(published, capture["published_raw_sha256"])
                self.assertTrue(capture["library_controls_restored"])
                self.assertEqual(2, len(self.case(name)["published_rows"]))

    def test_finite_provider_selection_preserves_sparse_bob_plates_and_bob_angel_boundaries(self):
        lua = self.lua()
        self.assertEqual("base", self._select(lua, self.case("base")["selection"]))
        self.assertEqual("space-age", self._select(lua, self.case("space_age")["selection"]))
        self.assertIsNone(self._select(lua, {"base": "2.1.23", "bobplates": "3.0.2"}))
        self.assertIsNone(self._select(lua, {"base": "2.1.23", "bobrevamp": "3.0.1"}))
        bob_angel = deepcopy(self.case("base")["selection"])
        bob_angel["angelssmelting"] = "2.1.1"
        self.assertIsNone(self._select(lua, bob_angel))

    def test_default_q005_q006_rebuilds_match_the_independent_b6_effect_vectors(self):
        for name in ("base", "space_age"):
            with self.subTest(name=name):
                rows, expected, flags = self._rebuild(name, 0.1)
                self.assertEqual({
                    "research_sulfur": True,
                    "research_sulfuric_acid_productivity": True,
                }, flags)
                observed = {row["name"]: row for row in rows}
                self.assertEqual(set(expected), set(observed))
                for technology_name, published in expected.items():
                    self.assertEqual(published["unit"], observed[technology_name]["unit"])
                    self.assertEqual(published["prerequisites"], observed[technology_name]["prerequisites"])
                    self.assertEqual(published["effects"], observed[technology_name]["effects"])
                    self.assertNotIn("sulfur", [row["recipe"] for row in observed[technology_name]["effects"]])
                    self.assertNotIn("sulfuric-acid", [row["recipe"] for row in observed[technology_name]["effects"]])

    def test_nondefault_stream_percent_scales_only_the_independent_b6_routes(self):
        for name in ("base", "space_age"):
            with self.subTest(name=name):
                rows, expected, _ = self._rebuild(name, 0.25)
                observed = {row["name"]: row for row in rows}
                for technology_name, published in expected.items():
                    self.assertEqual([effect["recipe"] for effect in published["effects"]],
                                     [effect["recipe"] for effect in observed[technology_name]["effects"]])
                    self.assertEqual([0.25] * len(published["effects"]),
                                     [effect["change"] for effect in observed[technology_name]["effects"]])

    def test_named_suppression_or_route_drift_refuses_without_raw_or_publication_writes(self):
        lua = self.lua()
        raw = deepcopy(self.case("space_age")["raw"])
        raw["recipe"]["sulfur"]["hidden"] = False
        before = deepcopy(raw)
        raw_lua = _lua_value(lua, raw)
        lua.globals().drifted_raw = raw_lua
        lua.globals().active_mods = _lua_value(lua, self.case("space_age")["selection"])
        ok, error = lua.execute(r'''
          local module = require("compatibility.bob_productivity")
          return pcall(function() module.preflight(drifted_raw, active_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("suppression changed: sulfur", error)
        self.assertEqual(before, _plain(raw_lua))

        routes = deepcopy(self.case("base")["raw"])
        routes["recipe"].pop("bob-sulfuric-acid-3")
        before = deepcopy(routes)
        routes_lua = _lua_value(lua, routes)
        lua.globals().drifted_raw = routes_lua
        lua.globals().active_mods = _lua_value(lua, self.case("base")["selection"])
        ok, error = lua.execute(r'''
          local module = require("compatibility.bob_productivity")
          return pcall(function() module.preflight(drifted_raw, active_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("route changed: bob-sulfuric-acid-3", error)
        self.assertEqual(before, _plain(routes_lua))

        neutralisation = deepcopy(self.case("space_age")["raw"])
        neutralisation["recipe"].pop("acid-neutralisation")
        before = deepcopy(neutralisation)
        neutralisation_lua = _lua_value(lua, neutralisation)
        lua.globals().drifted_raw = neutralisation_lua
        lua.globals().active_mods = _lua_value(lua, self.case("space_age")["selection"])
        ok, error = lua.execute(r'''
          data = setmetatable({}, {
            __index = function() error("Bob productivity preflight must not read prototype publication state") end,
            __newindex = function() error("Bob productivity preflight must not write prototype publication state") end,
          })
          local module = require("compatibility.bob_productivity")
          return pcall(function() module.preflight(drifted_raw, active_mods) end)
        ''')
        self.assertFalse(ok)
        self.assertIn("route changed: acid-neutralisation", error)
        self.assertEqual(before, _plain(neutralisation_lua))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(BobProductivityF210PipelineTests)
    )
    raise SystemExit(not result.wasSuccessful())
