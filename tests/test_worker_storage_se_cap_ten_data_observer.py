"""Lua52 controls for the data-only worker-storage cap-ten observer fixture.

The fixture reports active-mod and loaded startup-setting values only. These
host controls do not load Factorio, build an archive, or establish a cap-ten
research or gameplay result.
"""
import argparse
import math
from pathlib import Path
import sys
import tempfile
import unittest
import json


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/worker-storage-se-cap-ten"
SOURCE = FIXTURE / "data-final-fixes.lua"

SETTING_ORDER = (
    "mir-enable-worker-robots-storage",
    "mir-max-level-worker-robots-storage",
    "mir-cost-base-worker-robots-storage",
    "mir-cost-linear-increment-worker-robots-storage",
    "mir-cost-growth-worker-robots-storage",
    "mir-research-time-worker-robots-storage",
    "mir-effect-per-level-worker-robots-storage",
)
EXPECTED_VALUES = {
    "mir-enable-worker-robots-storage": True,
    "mir-max-level-worker-robots-storage": 10,
    "mir-cost-base-worker-robots-storage": 200,
    "mir-cost-linear-increment-worker-robots-storage": 0,
    "mir-cost-growth-worker-robots-storage": 1.5,
    "mir-research-time-worker-robots-storage": 60,
    "mir-effect-per-level-worker-robots-storage": 1,
}
PROTOTYPE_DEFAULTS = {
    "mir-enable-worker-robots-storage": False,
    **{name: 0 for name in SETTING_ORDER[1:]},
}
SELECTED_MODS = {
    "base": "2.0.77",
    "aai-containers": "0.3.2",
    "aai-industry": "0.6.16",
    "aai-signal-transmission": "0.5.3",
    "alien-biomes": "0.7.4",
    "alien-biomes-graphics": "0.7.1",
    "informatron": "0.4.0",
    "jetpack": "0.4.17",
    "robot_attrition": "0.6.6",
    "shield-projector": "0.2.2",
    "space-exploration": "0.7.57",
    "space-exploration-graphics": "0.7.5",
    "space-exploration-graphics-2": "0.7.2",
    "space-exploration-graphics-3": "0.7.2",
    "space-exploration-graphics-4": "0.7.2",
    "space-exploration-graphics-5": "0.7.3",
    "space-exploration-menu-simulations": "0.7.4",
    "space-exploration-postprocess": "0.7.5",
    "mir-fixture-mir5-worker-storage-se-cap-ten-observer": "0.1.0",
    "more-infinite-research": "4.7.20002",
}


def marker_value(value):
    if isinstance(value, bool):
        return f"boolean:{str(value).lower()}"
    return f"number:{value}"


def expected_settings_marker(values):
    return "[MIR_WORKER_STORAGE_SETTINGS] " + "|".join(
        f"{name}={marker_value(values[name])}" for name in SETTING_ORDER
    )


class WorkerStorageSECapTenDataObserverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.execute(r"""
          function readonly(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] ~= nil then return seen[value] end
            local backing = {}
            local proxy = {}
            seen[value] = proxy
            for key, child in pairs(value) do
              backing[readonly(key, seen)] = readonly(child, seen)
            end
            return setmetatable(proxy, {
              __index = backing,
              __newindex = function(_, key)
                error("fixture mutation refused for " .. tostring(key))
              end,
              __pairs = function() return pairs(backing) end,
              __metatable = "locked"
            })
          end

          function execute_cap_ten_observer(path, supplied_mods, supplied_settings)
            local lines = {}
            local environment = {
              log = function(message) lines[#lines + 1] = message end,
              mods = readonly(supplied_mods),
              settings = readonly(supplied_settings),
              data = setmetatable({}, {
                __index = function() error("fixture data API must remain unread") end,
                __newindex = function() error("fixture data API must remain unwritten") end
              })
            }
            setmetatable(environment, {__index = function(_, key) return _G[key] end})
            local chunk, message = loadfile(path, "t", environment)
            if chunk == nil then return false, message, lines end
            local ok, result = pcall(chunk)
            return ok, result, lines
          end
        """)

    def lua_value(self, value):
        if isinstance(value, dict):
            table = self.lua.table()
            for key, child in value.items():
                table[key] = self.lua_value(child)
            return table
        return value

    def run_fixture(self, *, values=EXPECTED_VALUES, mods=SELECTED_MODS, source=SOURCE):
        rows = {
            name: {"value": value, "default_value": PROTOTYPE_DEFAULTS[name]}
            for name, value in values.items()
        }
        self.lua.globals().fixture_path = source.as_posix()
        self.lua.globals().fixture_mods = self.lua_value(mods)
        self.lua.globals().fixture_settings = self.lua_value({"startup": rows})
        ok, result, logs = self.lua.eval(
            "execute_cap_ten_observer(fixture_path, fixture_mods, fixture_settings)"
        )
        return ok, result, [logs[index] for index in range(1, len(logs) + 1)]

    def test_fixture_metadata_is_data_only_and_requires_mir(self):
        for member, family, minimum in (("info.json", "2.1", "2.1.23"),
                                        ("info-f200.json", "2.0", "2.0.77")):
            with self.subTest(member=member):
                info = json.loads((FIXTURE / member).read_text(encoding="utf-8"))
                self.assertEqual(info["name"], "mir-fixture-mir5-worker-storage-se-cap-ten-observer")
                self.assertEqual(info["version"], "0.1.0")
                self.assertEqual(info["factorio_version"], family)
                self.assertEqual(info["dependencies"], [f"base >= {minimum}", "more-infinite-research"])
        self.assertEqual(sorted(path.name for path in FIXTURE.iterdir()),
                         ["README.md", "data-final-fixes.lua", "info-f200.json", "info.json"])
        self.assertNotIn("control.lua", "\n".join(path.name for path in FIXTURE.iterdir()))

    def test_reports_actual_cap_ten_values_not_prototype_defaults(self):
        ok, result, logs = self.run_fixture()
        self.assertTrue(ok, result)
        self.assertEqual(len(SELECTED_MODS), 20)
        self.assertEqual(logs, [
            "[MIR_ACTIVE_MODS] " + "|".join(sorted(
                f"{name}@{version}" for name, version in SELECTED_MODS.items()
            )),
            expected_settings_marker(EXPECTED_VALUES),
        ])
        self.assertNotEqual(expected_settings_marker(EXPECTED_VALUES),
                            expected_settings_marker(PROTOTYPE_DEFAULTS))
        self.assertNotIn("default_value", SOURCE.read_text(encoding="utf-8"))

    def test_preserves_false_and_zero_as_observed_values(self):
        values = dict(EXPECTED_VALUES)
        values.update({name: 0 for name in SETTING_ORDER[1:]})
        values[SETTING_ORDER[0]] = False
        ok, result, logs = self.run_fixture(values=values)
        self.assertTrue(ok, result)
        self.assertEqual(logs[1], expected_settings_marker(values))

    def test_mod_and_settings_markers_are_deterministic(self):
        reversed_mods = dict(reversed(tuple(SELECTED_MODS.items())))
        first = self.run_fixture(mods=SELECTED_MODS)
        second = self.run_fixture(mods=reversed_mods)
        self.assertTrue(first[0], first[1])
        self.assertTrue(second[0], second[1])
        self.assertEqual(first[2], second[2])

    def test_refuses_each_missing_setting_with_key_and_observed_reason(self):
        for name in SETTING_ORDER:
            with self.subTest(name=name):
                values = dict(EXPECTED_VALUES)
                del values[name]
                ok, result, _ = self.run_fixture(values=values)
                self.assertFalse(ok)
                self.assertIn(name, result)
                self.assertIn("missing setting row observed=nil", result)

    def test_refuses_wrong_setting_types_with_key_and_observed_reason(self):
        for name in SETTING_ORDER:
            with self.subTest(name=name):
                values = dict(EXPECTED_VALUES)
                values[name] = 1 if name == SETTING_ORDER[0] else False
                ok, result, _ = self.run_fixture(values=values)
                self.assertFalse(ok)
                self.assertIn(name, result)
                self.assertIn("wrong type expected=", result)
                self.assertIn("observed=", result)

    def test_refuses_nonfinite_numeric_settings(self):
        for value in (math.nan, math.inf, -math.inf):
            with self.subTest(value=value):
                values = dict(EXPECTED_VALUES)
                values["mir-max-level-worker-robots-storage"] = value
                ok, result, _ = self.run_fixture(values=values)
                self.assertFalse(ok)
                self.assertIn("mir-max-level-worker-robots-storage", result)
                self.assertIn("nonfinite observed=number:", result)

    def test_read_only_mod_settings_and_data_proxies_refuse_mutant_writes(self):
        source = SOURCE.read_text(encoding="utf-8")
        mutations = {
            "mods": "\nmods['base'] = 'mutated'\n",
            "settings": "\nsettings.startup['mir-max-level-worker-robots-storage'].value = 999\n",
            "data": "\ndata.raw = {}\n",
        }
        with tempfile.TemporaryDirectory(prefix="mir5-cap-ten-observer-mutant-") as directory:
            for name, mutation in mutations.items():
                with self.subTest(name=name):
                    mutant = Path(directory) / f"{name}.lua"
                    mutant.write_text(source + mutation, encoding="utf-8", newline="\n")
                    ok, result, _ = self.run_fixture(source=mutant)
                    self.assertFalse(ok)
                    self.assertIn("fixture", result)

    def test_value_to_default_value_mutant_is_rejected_by_actual_marker_oracle(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertEqual(source.count("row.value"), 1)
        mutant_source = source.replace("row.value", "row.default_value", 1)
        with tempfile.TemporaryDirectory(prefix="mir5-cap-ten-observer-default-mutant-") as directory:
            mutant = Path(directory) / "default-value-mutant.lua"
            mutant.write_text(mutant_source, encoding="utf-8", newline="\n")
            ok, result, logs = self.run_fixture(source=mutant)
        self.assertTrue(ok, result)
        self.assertNotEqual(logs[1], expected_settings_marker(EXPECTED_VALUES))
        self.assertEqual(logs[1], expected_settings_marker(PROTOTYPE_DEFAULTS))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(WorkerStorageSECapTenDataObserverTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
