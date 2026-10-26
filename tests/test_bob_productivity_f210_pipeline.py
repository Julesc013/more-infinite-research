"""Independent q005/q006 F210 full-Bob sulfur and acid target controls."""

import argparse
from copy import deepcopy
import gzip
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "source"
CONTEXT_PATH = ROOT / "tests/fixtures/bob-productivity-f210-upstream-context.json"
PIPELINE_CONTEXT_PATH = ROOT / "tests/fixtures/bob-warfare-f210-upstream-context.json.gz"
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
        cls.pipeline_context = json.loads(gzip.decompress(PIPELINE_CONTEXT_PATH.read_bytes()))
        if cls.pipeline_context.get("schema") != "MIR5BobWarfareF210PipelineContextV1":
            raise AssertionError("Bob productivity pipeline context schema changed")

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

    def _pipeline_case(self, name):
        return self.pipeline_context["cases"]["q006" if name == "space_age" else "q005"]

    def _stage_pipeline(self, name, startup=None, mutate=None):
        case = self._pipeline_case(name)
        raw = deepcopy(case["raw"])
        if mutate is not None:
            mutate(raw)
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, raw)
        lua.globals().active_mods = _lua_value(lua, deepcopy(case["selection"]))
        lua.globals().startup_values = _lua_value(lua, startup or {})
        lua.execute(r'''
          mods, script, helpers, log = active_mods, nil, {}, function() end
          settings = {startup = startup_values}
          data = {raw = captured_raw}
          emitted, technology_publications = {}, 0
          function data:extend(rows)
            local wrote_technology = false
            for _, row in ipairs(rows) do
              self.raw[row.type] = self.raw[row.type] or {}
              assert(self.raw[row.type][row.name] == nil, "duplicate " .. row.type .. ":" .. row.name)
              self.raw[row.type][row.name] = row
              if row.type == "technology" then
                emitted[row.name] = row
                wrote_technology = true
              end
            end
            if wrote_technology then technology_publications = technology_publications + 1 end
          end
          assert(loadfile(player_root .. "/settings.lua"))()
          for _, spec in ipairs(require("research.settings").prototypes()) do
            if settings.startup[spec.name] == nil then settings.startup[spec.name] = {value = spec.default_value} end
          end
          assert(loadfile(player_root .. "/data.lua"))()
          emitted, technology_publications = {}, 0
          outcome, message = pcall(function() assert(loadfile(player_root .. "/data-final-fixes.lua"))() end)
        ''')
        return lua

    @staticmethod
    def _technology_vector(row):
        return {
            "unit": row["unit"],
            "prerequisites": row.get("prerequisites", []),
            "effects": row.get("effects", []),
        }

    def _catalogue_selection(self, name):
        case = self._pipeline_case(name)
        lua = self.lua()
        lua.globals().captured_raw = _lua_value(lua, deepcopy(case["raw"]))
        lua.globals().active_mods = _lua_value(lua, deepcopy(case["selection"]))
        return _plain(lua.execute('return require("compatibility.modern_catalogue").select(active_mods, captured_raw)'))

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

    def test_full_settings_data_final_pipeline_matches_independent_q005_q006_b6_vectors(self):
        for name in ("base", "space_age"):
            with self.subTest(name=name):
                case = self.case(name)
                pipeline = self._pipeline_case(name)
                self.assertEqual(case["capture"]["upstream_raw_sha256"], pipeline["provenance"]["upstream"]["raw_sha256"])
                self.assertEqual(case["capture"]["published_raw_sha256"], pipeline["provenance"]["published"]["raw_sha256"])
                lua = self._stage_pipeline(name)
                self.assertTrue(lua.globals().outcome, str(lua.globals().message))
                emitted = _plain(lua.globals().emitted)
                for technology_name, expected in case["published_rows"].items():
                    self.assertIn(technology_name, emitted)
                    self.assertEqual(self._technology_vector(expected), self._technology_vector(emitted[technology_name]))
                self.assertEqual(1, lua.globals().technology_publications)

                selected = self._catalogue_selection(name)
                self.assertEqual(name.replace("_", "-"), selected["bob_productivity"])
                self.assertTrue(selected["replacement_product_target_families"]["research_sulfur"])
                self.assertTrue(selected["replacement_product_target_families"]["research_sulfuric_acid_productivity"])

    def test_sparse_bob_angel_and_f200_boundaries_do_not_select_the_f210_replacement_profile(self):
        lua = self.lua()
        module = self._module(lua)
        self.assertIsNone(module["select"](_lua_value(lua, {"base": "2.1.23", "bobplates": "3.0.2"})))
        angel = deepcopy(self.case("base")["selection"])
        angel["angelssmelting"] = "2.1.1"
        self.assertIsNone(module["select"](_lua_value(lua, angel)))

        lua.execute('local target = require("platform.target"); target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"')
        self.assertIsNone(module["select"](_lua_value(lua, self.case("base")["selection"])))

        # A non-selected profile must not load its data preflight module at
        # all. The packager's static closure still includes the pure module.
        for target_id in ("f200", "f210"):
            isolated = self.lua()
            isolated.globals().selected_target = target_id
            loaded = isolated.execute(r'''
              local target = require("platform.target")
              target.id = selected_target
              if selected_target == "f200" then
                target.factorio_version, target.minimum_base, target.cargo_research = "2.0", "2.0.77", false
              end
              require("compatibility.modern_catalogue").select({base = target.minimum_base})
              return package.loaded["compatibility.bob_productivity"]
            ''')
            self.assertIsNone(loaded)

    def test_full_pipeline_configured_percent_and_disabled_streams_preserve_the_declared_boundary(self):
        configured = {
            "ips-effect-per-level-research_sulfur": {"value": 25},
            "ips-effect-per-level-research_sulfuric_acid_productivity": {"value": 25},
        }
        lua = self._stage_pipeline("space_age", configured)
        self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        emitted = _plain(lua.globals().emitted)
        for technology_name in self.case("space_age")["published_rows"]:
            self.assertEqual([0.25] * len(emitted[technology_name]["effects"]),
                             [effect["change"] for effect in emitted[technology_name]["effects"]])

        disabled = {
            "ips-enable-research_sulfur": {"value": False},
            "ips-enable-research_sulfuric_acid_productivity": {"value": False},
        }
        lua = self._stage_pipeline("base", disabled)
        self.assertTrue(lua.globals().outcome, str(lua.globals().message))
        emitted = _plain(lua.globals().emitted)
        for technology_name, expected in self.case("base")["published_rows"].items():
            self.assertIn(technology_name, emitted)
            self.assertFalse(emitted[technology_name]["enabled"])
            self.assertEqual(expected["effects"], emitted[technology_name]["effects"])

    def test_full_pipeline_named_route_drift_refuses_before_any_technology_publication(self):
        def mutate(raw):
            raw["recipe"].pop("bob-sulfuric-acid-3")

        lua = self._stage_pipeline("base", mutate=mutate)
        self.assertFalse(lua.globals().outcome)
        self.assertIn("MIR Bob productivity route changed: bob-sulfuric-acid-3", str(lua.globals().message))
        self.assertEqual(0, lua.globals().technology_publications)

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
