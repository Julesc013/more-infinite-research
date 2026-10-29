"""Focused F200 native-continuation bindings from captured published rows only."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "source"
FACTS_PATH = ROOT / "tests/fixtures/native-modded-continuations-f200-captured-facts.json"


def _lua_value(lua, value):
    if isinstance(value, dict):
        result = lua.table()
        for key, nested in value.items():
            result[key] = _lua_value(lua, nested)
        return result
    if isinstance(value, list):
        result = lua.table()
        for index, nested in enumerate(value, 1):
            result[index] = _lua_value(lua, nested)
        return result
    return value


def _plain(value):
    if not hasattr(value, "items"):
        return value
    values = dict(value.items())
    if values and set(values) == set(range(1, len(values) + 1)):
        return [_plain(values[index]) for index in range(1, len(values) + 1)]
    return {key: _plain(item) for key, item in values.items()}


def _overlay(destination, changes):
    for key, value in changes.items():
        if isinstance(value, dict) and isinstance(destination.get(key), dict):
            _overlay(destination[key], value)
        else:
            destination[key] = deepcopy(value)


BASE_PREDECESSORS = {
    "braking-force-8": {
        "prerequisites": ["braking-force-6"],
        "effects": [{"type": "train-braking-force-bonus", "modifier": 0.15}],
    },
    "inserter-capacity-bonus-8": {
        "prerequisites": ["utility-science-pack", "inserter-capacity-bonus-6"],
        "effects": [{"type": "inserter-stack-size-bonus", "modifier": 1},
                    {"type": "bulk-inserter-capacity-bonus", "modifier": 2}],
    },
    "laser-shooting-speed-8": {
        "prerequisites": ["laser-shooting-speed-6"],
        "effects": [{"type": "gun-speed", "ammo_category": "laser", "modifier": 0.5}],
    },
    "research-speed-7": {
        "prerequisites": ["utility-science-pack", "research-speed-5"],
        "effects": [{"type": "laboratory-speed", "modifier": 0.6}],
    },
    "weapon-shooting-speed-7": {
        "prerequisites": ["utility-science-pack", "weapon-shooting-speed-5"],
        "effects": [{"type": "gun-speed", "ammo_category": "bullet", "modifier": 0.4},
                    {"type": "gun-speed", "ammo_category": "shotgun-shell", "modifier": 0.4},
                    {"type": "gun-speed", "ammo_category": "cannon-shell", "modifier": 1.5},
                    {"type": "gun-speed", "ammo_category": "rocket", "modifier": 1.3}],
    },
    "worker-robots-storage-4": {
        "prerequisites": ["utility-science-pack", "worker-robots-storage-2"],
        "effects": [{"type": "worker-robot-storage", "modifier": 1}],
    },
}

RESEARCH_SPEED_ICONS = [
    {"icon": "__pycoalprocessinggraphics__/graphics/technology/energy-1.png", "icon_size": 128,
     "tint": {"r": 0, "g": 0, "b": 0, "a": 1}},
    {"icon": "__pycoalprocessinggraphics__/graphics/technology/border.png", "icon_size": 128},
    {"icon": "__pycoalprocessinggraphics__/graphics/technology/lab.png", "icon_size": 128, "scale": 0.8},
    {"icon": "__core__/graphics/icons/technology/constants/constant-speed.png", "icon_size": 128,
     "scale": 0.5, "shift": [50, 50]},
]

TAIL_BY_PREDECESSOR = {
    "braking-force-7": "braking-force-8",
    "inserter-capacity-bonus-7": "inserter-capacity-bonus-8",
    "laser-shooting-speed-7": "laser-shooting-speed-8",
    "research-speed-6": "research-speed-7",
    "weapon-shooting-speed-6": "weapon-shooting-speed-7",
    "worker-robots-storage-3": "worker-robots-storage-4",
}


class NativeModdedContinuationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.facts = json.loads(FACTS_PATH.read_text(encoding="utf-8"))
        if cls.facts["status"] != "hash-verified-published-data-stage-reference-only":
            raise AssertionError("native continuation facts lost their evidence limit")
        cls.profiles = {profile["id"]: profile for profile in cls.facts["profiles"]}
        if set(cls.profiles) != {"armor-bobwarfare", "py-coal", "py-alienlife-hightech"}:
            raise AssertionError("native continuation profile set drifted")
        if set(cls.facts["common_published_rows"]) != {
            "braking-force-8", "inserter-capacity-bonus-8", "laser-shooting-speed-8",
            "research-speed-7", "weapon-shooting-speed-7", "worker-robots-storage-4",
        }:
            raise AssertionError("native continuation tail set drifted")

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().player_root = PLAYER.as_posix()
        self.lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          target.distribution_version, target.cargo_research = "5.0.20000", false
          target.recipe_probability, target.productivity_ignores_stats, target.receiver_limits = "probability", true, false
        ''')
        self.catalogue = self.lua.execute('return require("compatibility.modern_catalogue")')
        self.continuations = self.lua.execute('return require("compatibility.native_modded_continuations")')
        self.modern = self.lua.execute('return require("research.modern")')

    def _expected_rows(self, profile):
        expected = deepcopy(self.facts["common_published_rows"])
        for name, fields in profile["published_field_changes"].items():
            _overlay(expected[name], fields)
        return expected

    @staticmethod
    def _values(effect_percent=0.0, research_time=None, inherit_costs=False):
        values = {
            "braking-force": (115, 1.333333333333, 15, 60),
            "inserter-capacity-bonus": (200, 3.333333333333, 4, 60),
            "laser-shooting-speed": (60, 1.5, 50, 120),
            "research-speed": (60, 1.5, 60, 120),
            "weapon-shooting-speed": (60, 1.5, 40, 120),
            "worker-robots-storage": (200, 1.5, 1, 60),
        }
        streams = {}
        for family, (base_cost, growth, default_effect, default_time) in values.items():
            streams[family] = {
                "base_cost": 0 if inherit_costs else base_cost,
                "linear_increment": 0,
                "growth_factor": 0 if inherit_costs else growth,
                "effect_percent": effect_percent or default_effect,
                "research_time": default_time if research_time is None else research_time,
                "enabled": True,
            }
        return {"streams": streams}

    def _selected_tails(self, profile):
        selection = self.catalogue["select"](_lua_value(self.lua, profile["active_mods"]))
        return {row["id"]: row for row in _plain(selection["continuations"])}

    def _emitted_rows(self, profile, values=None):
        values = values or self._values()
        selected = self._selected_tails(profile)
        return {
            identifier: _plain(self.modern["continuation"](_lua_value(self.lua, definition), _lua_value(self.lua, values)))
            for identifier, definition in selected.items()
        }

    def _raw_for(self, profile):
        raw = {"technology": {}, "writes": 0}
        if profile["id"] == "armor-bobwarfare":
            bindings = profile["preflight"]
            for binding in bindings:
                previous, predecessor = binding["previous"], binding["predecessor"]
                raw["technology"][previous["name"]] = {"unit": {"count": previous["count"]}}
                raw["technology"][predecessor["name"]] = {
                    "unit": {"count": predecessor["count"], "time": predecessor["time"],
                             "ingredients": deepcopy(predecessor["ingredients"])},
                    "prerequisites": deepcopy(predecessor["prerequisites"]),
                    "effects": deepcopy(predecessor["effects"]),
                }
                for name, _ in predecessor["ingredients"]:
                    raw["technology"].setdefault(name, {})
            return raw

        time = 60 if profile["id"] == "py-coal" else 600
        science = deepcopy(profile["preflight_science"])
        changes = profile["published_field_changes"]
        for previous, previous_count, predecessor, predecessor_count in profile["preflight_counts"]:
            tail = TAIL_BY_PREDECESSOR[predecessor]
            spec = BASE_PREDECESSORS[tail]
            native = {
                "unit": {"count": predecessor_count, "time": time, "ingredients": deepcopy(science)},
                "prerequisites": deepcopy(spec["prerequisites"]), "effects": deepcopy(spec["effects"]),
                "order": changes[tail]["order"],
            }
            if tail == "research-speed-7":
                native["icon_size"], native["icons"] = 128, deepcopy(RESEARCH_SPEED_ICONS)
            raw["technology"][previous] = {"unit": {"count": previous_count}}
            raw["technology"][predecessor] = native
        for name, _ in science:
            raw["technology"].setdefault(name, {})
        return raw

    def test_complete_captured_rows_are_emitted_for_each_profile(self):
        for profile in self.profiles.values():
            with self.subTest(profile=profile["id"]):
                self.assertEqual(self._expected_rows(profile), self._emitted_rows(profile))

    def test_preflight_rejects_named_predecessor_and_effect_drift_without_writes(self):
        for profile in self.profiles.values():
            with self.subTest(profile=profile["id"], drift="predecessor"):
                raw = self._raw_for(profile)
                lua_raw = _lua_value(self.lua, raw)
                untouched = _plain(lua_raw)
                self.assertTrue(self.continuations["preflight"](
                    _lua_value(self.lua, profile["active_mods"]), lua_raw))
                self.assertEqual(untouched, _plain(lua_raw))

                bad = self._raw_for(profile)
                previous = next(name for name in bad["technology"] if name.endswith("-6"))
                bad["technology"][previous]["unit"]["count"] += 1
                lua_bad = _lua_value(self.lua, bad)
                before = _plain(lua_bad)
                with self.assertRaisesRegex(Exception, "previous inherited cost changed"):
                    self.continuations["preflight"](_lua_value(self.lua, profile["active_mods"]), lua_bad)
                self.assertEqual(before, _plain(lua_bad))

            with self.subTest(profile=profile["id"], drift="effect"):
                bad = self._raw_for(profile)
                if profile["id"] == "armor-bobwarfare":
                    predecessor = "laser-shooting-speed-7"
                else:
                    predecessor = "weapon-shooting-speed-6"
                bad["technology"][predecessor]["effects"][0]["modifier"] = 999
                lua_bad = _lua_value(self.lua, bad)
                before = _plain(lua_bad)
                with self.assertRaisesRegex(Exception, "predecessor effects changed"):
                    self.continuations["preflight"](_lua_value(self.lua, profile["active_mods"]), lua_bad)
                self.assertEqual(before, _plain(lua_bad))

    def test_overrides_are_detached_and_inactive_catalogue_selection_does_not_load_the_body(self):
        for profile in self.profiles.values():
            with self.subTest(profile=profile["id"]):
                first = self.continuations["continuation_overrides"](_lua_value(self.lua, profile["active_mods"]))
                first["laser-shooting-speed-8"]["effects"] = self.lua.table()
                if profile["id"] != "armor-bobwarfare":
                    first["research-speed-7"]["science_amounts"]["automation-science-pack"] = -1
                    first["research-speed-7"]["icons"][1]["icon"] = "corrupted"
                second = _plain(self.continuations["continuation_overrides"](_lua_value(self.lua, profile["active_mods"])))
                if profile["id"] == "armor-bobwarfare":
                    self.assertEqual("bob-laser-rifle", second["laser-shooting-speed-8"]["effects"][1]["ammo_category"])
                else:
                    self.assertEqual(10 if profile["id"] == "py-coal" else 100,
                                     second["research-speed-7"]["science_amounts"]["automation-science-pack"])
                    self.assertEqual("__pycoalprocessinggraphics__/graphics/technology/energy-1.png",
                                     second["research-speed-7"]["icons"][0]["icon"])

        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().player_root = PLAYER.as_posix()
        lua.execute(r'''
          package.path = player_root .. "/?.lua;" .. player_root .. "/?/init.lua"
          package.cpath = ""
          target = require("platform.target")
          target.id, target.factorio_version, target.minimum_base = "f200", "2.0", "2.0.77"
          require("compatibility.modern_catalogue").select({base="2.0.77"})
        ''')
        self.assertIsNone(lua.globals().package.loaded["compatibility.native_modded_continuations"])

    def test_different_settings_preserve_profile_specific_inheritance_offsets(self):
        expected_formula = {
            "armor-bobwarfare": "578.557886434211*1.28571^(L-8)",
            "py-coal": "2750",
            "py-alienlife-hightech": "4000",
        }
        expected_time = {"armor-bobwarfare": 60, "py-coal": 60, "py-alienlife-hightech": 600}
        for identifier, profile in self.profiles.items():
            with self.subTest(profile=identifier):
                rows = self._emitted_rows(profile, self._values(effect_percent=25, research_time=0, inherit_costs=True))
                laser = rows["laser-shooting-speed-8"]
                self.assertEqual(expected_formula[identifier], laser["unit"]["count_formula"])
                self.assertEqual(expected_time[identifier], laser["unit"]["time"])
                self.assertEqual(0.25, laser["effects"][0]["modifier"])
                if identifier == "armor-bobwarfare":
                    self.assertEqual(0.25, laser["effects"][1]["modifier"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(NativeModdedContinuationTests)
    )
    sys.exit(0 if result.wasSuccessful() else 1)
