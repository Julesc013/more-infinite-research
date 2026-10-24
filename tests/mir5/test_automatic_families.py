"""F200 automatic-family non-emission controls; no automatic research is authored here."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest

from native_credit_oracle import verified_public_rows


ROOT = Path(__file__).resolve().parents[2]
FACTS_PATH = ROOT / "tests/mir5/fixtures/automatic-families-f200-captured-facts.json"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _lua_value(lua, value):
    if isinstance(value, dict):
        result = lua.table()
        for key, nested in value.items():
            result[key] = _lua_value(lua, nested)
        return result
    if isinstance(value, list):
        result = lua.table()
        for index, nested in enumerate(value, start=1):
            result[index] = _lua_value(lua, nested)
        return result
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(nested) for key, nested in values.items()}


def _load_generator_harness():
    """Use the existing complete data-final host world, not a name-only mock."""
    path = ROOT / "tests/mir5/test_generator.py"
    spec = importlib.util.spec_from_file_location("_automatic_family_generator_harness", path)
    if spec is None or spec.loader is None:
        raise AssertionError("cannot load the MIR5 Generator host harness")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.LuaRuntime = LuaRuntime
    harness = module.GeneratorTests()
    harness.setUp()
    return harness


class AutomaticFamilyNonEmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        if cls.facts.get("kind") != "mir5-f200-automatic-family-non-emission-facts":
            raise AssertionError("automatic-family captured-fact fixture kind drifted")
        if cls.facts["target"] != {
            "id": "f200", "factorio_version": "2.0", "minimum_base": "2.0.77"
        }:
            raise AssertionError("automatic-family facts no longer name F200 Base 2.0.77")

        for group, paths in (
            ("observer_fixture", (("info_path", "info_sha256"), ("settings_path", "settings_sha256"))),
            ("historical_source_evidence", (
                ("streams_path", "streams_sha256"),
                ("providers_path", "providers_sha256"),
                ("matcher_path", "matcher_sha256"),
                ("historical_settings_path", "historical_settings_sha256"),
            )),
            ("historical_fixture_only_evidence", (("create_path", "create_sha256"), ("load_path", "load_sha256"))),
        ):
            record = cls.facts[group]
            for path_key, hash_key in paths:
                path = ROOT / record[path_key]
                if _sha256(path) != record[hash_key]:
                    raise AssertionError(f"automatic-family source evidence changed: {path}")

        profile = ROOT / cls.facts["profile"]
        if _sha256(profile) != cls.facts["profile_sha256"]:
            raise AssertionError("automatic-family profile selection changed")
        parsed_profile = json.loads(profile.read_text(encoding="utf-8"))
        if (parsed_profile.get("target") != "f200"
                or parsed_profile.get("engine", {}).get("version") != "2.0.77"):
            raise AssertionError("automatic-family profile no longer selects F200 Base 2.0.77")

        absent = cls.facts["published_raw"]["absent_generated_ids"]
        if absent != [
            "mir-auto-prod-manufacturing-assembling-machine-1",
            "mir-auto-prod-manufacturing-lab-1",
        ]:
            raise AssertionError("automatic-family non-emission identities drifted")
        routes = cls.facts["native_routes"]
        if [route["recipe"] for route in routes] != [
            "assembling-machine-1", "assembling-machine-2", "assembling-machine-3", "lab"
        ]:
            raise AssertionError("automatic-family native route scope drifted")
        if any(route["allow_productivity"] != "omitted" for route in routes):
            raise AssertionError("automatic-family disposition requires omitted native productivity permission")

    @staticmethod
    def _verify_raw_routes(raw, facts):
        for route in facts["native_routes"]:
            item = raw.get("item", {}).get(route["item"])
            recipe = raw.get("recipe", {}).get(route["recipe"])
            entity = raw.get(route["entity_type"], {}).get(route["place_result"])
            if (not isinstance(item, dict) or item.get("icon") != route["item_icon"]
                    or item.get("place_result") != route["place_result"]
                    or not isinstance(entity, dict)):
                raise AssertionError(f"automatic-family item/entity fact drifted: {route['item']}")
            if (not isinstance(recipe, dict) or recipe.get("enabled") is not route["enabled"]
                    or recipe.get("hidden") is not None
                    or recipe.get("allow_productivity") is not None
                    or recipe.get("maximum_productivity") is not None
                    or recipe.get("ingredients") != route["ingredients"]
                    or recipe.get("results") != route["results"]):
                raise AssertionError(f"automatic-family recipe fact drifted: {route['recipe']}")

    @staticmethod
    def _verify_published_settings(raw, facts):
        settings = raw.get("bool-setting", {})
        for name, value in facts["observer_fixture"]["resolved_startup_defaults"].items():
            if name in settings:
                actual = settings[name].get("default_value")
            else:
                actual = raw.get("string-setting", {}).get(name, {}).get("default_value")
            if actual != value:
                raise AssertionError(f"automatic-family observer setting drifted: {name}")

    def test_portable_disposition_pins_old_explicit_gate_and_fixture_only_history(self):
        evidence = self.facts["historical_source_evidence"]
        matcher = (ROOT / evidence["matcher_path"]).read_text(encoding="utf-8")
        self.assertIn(evidence["matcher_required_literal"], matcher)

        streams = (ROOT / evidence["streams_path"]).read_text(encoding="utf-8")
        providers = (ROOT / evidence["providers_path"]).read_text(encoding="utf-8")
        settings = (ROOT / evidence["historical_settings_path"]).read_text(encoding="utf-8")
        for family in ("research_auto_assembling_machine", "research_auto_lab"):
            self.assertIn(family, streams)
            self.assertIn(family, providers)
            self.assertIn(family, settings)

        history = self.facts["historical_fixture_only_evidence"]
        for key in ("create_path", "load_path"):
            text = (ROOT / history[key]).read_text(encoding="utf-8")
            self.assertIn(history["emitted_identity"], text)
            self.assertIn(history["fixture_recipe"], text)
            self.assertIn(history["withheld_family_log"], text)
        self.assertEqual(
            self.facts["disposition"]["f200_base"], "withhold-both-automatic-identities"
        )

    def test_local_matched_capture_proves_opt_in_and_no_generated_auto_ids_when_present(self):
        upstream_info = self.facts["upstream_raw"]
        published_info = self.facts["published_raw"]
        upstream_path = ROOT / upstream_info["path"]
        published_path = ROOT / published_info["path"]
        if not (upstream_path.is_file() and published_path.is_file()):
            self.skipTest("developer-custody raw captures are optional; portable facts remain checked")
        self.assertEqual(_sha256(upstream_path), upstream_info["sha256"])
        self.assertEqual(_sha256(published_path), published_info["sha256"])
        upstream = json.loads(upstream_path.read_text(encoding="utf-8"))
        published = json.loads(published_path.read_text(encoding="utf-8"))
        self._verify_raw_routes(upstream, self.facts)
        self._verify_raw_routes(published, self.facts)

        emitted = set(published.get("technology", {})) - set(upstream.get("technology", {}))
        self.assertEqual(len(emitted), published_info["generated_technology_count"])
        self.assertTrue(emitted, "matched published capture has no generated rows")
        self.assertTrue(emitted.isdisjoint(published_info["absent_generated_ids"]))

        settings_path = ROOT / published_info["settings_path"]
        if settings_path.is_file():
            self.assertEqual(_sha256(settings_path), published_info["settings_sha256"])
            self._verify_published_settings(json.loads(settings_path.read_text(encoding="utf-8")), self.facts)

    def test_full_f200_data_final_pipeline_keeps_opt_in_but_does_not_emit_automatic_ids(self):
        harness = _load_generator_harness()
        self.addCleanup(lambda: setattr(harness, "lua", None))
        lua = harness.lua
        lua.globals().automatic_facts = _lua_value(lua, self.facts)
        lua.execute(r'''
          local target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.receiver_limits = "probability", false
          target.productivity_ignores_stats = true
          package.loaded["research.settings"] = nil
          config = require("research.settings")

          local startup = defaults()
          for name, value in pairs(automatic_facts.observer_fixture.resolved_startup_defaults) do
            assert(startup[name] ~= nil, "missing retained automatic setting " .. name)
            startup[name].value = value
          end
          local values = config.resolve(startup)
          assert(values.options["mir-automatic-create-research"] == true)
          assert(values.options["mir-automatic-require-reviewed-data"] == false)
          assert(values.options["mir-automatic-productivity-action"] == "apply")
          assert(values.options["mir-automatic-compiler-mode"] == "safe-attach")

          mods = {base = "2.0.77"}
          data = full_world(mods)
          for _, route in ipairs(automatic_facts.native_routes) do
            data.raw.item[route.item] = {icon=route.item_icon, place_result=route.place_result}
            data.raw.recipe[route.recipe] = {
              enabled=route.enabled, ingredients=route.ingredients, results=route.results
            }
            data.raw[route.entity_type] = data.raw[route.entity_type] or {}
            data.raw[route.entity_type][route.place_result] = {}
          end
          settings, helpers, log = {startup=startup}, nil, function() end
          assert(dofile(data_final_path) == nil)
          assert(data.writes == 1)
          local emitted = {}
          for _, row in ipairs(data.emitted) do emitted[row.name] = true end
          for _, name in ipairs(automatic_facts.published_raw.absent_generated_ids) do
            assert(not emitted[name], "unqualified automatic family emitted: " .. name)
          end
          for _, route in ipairs(automatic_facts.native_routes) do
            assert(data.raw.recipe[route.recipe].allow_productivity == nil,
              "Base route acquired a productivity permission: " .. route.recipe)
          end
        ''')
        emitted = {
            row["name"]: _plain(row)
            for row in lua.globals().data.emitted.values()
        }
        public = verified_public_rows(
            emitted,
            {str(name) for name in lua.globals().data.raw.recipe.keys()},
        )
        self.assertEqual(len(public), self.facts["published_raw"]["generated_technology_count"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(AutomaticFamilyNonEmissionTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
