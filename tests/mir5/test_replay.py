"""Synthetic host tests for the offline MIR 5 diagnostic replay builder.

These fixtures model capture records only.  They are deliberately not Factorio
executions or a claim that the generated diagnostic reference loads natively.
"""
import argparse
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REPLAY_PATH = ROOT / "tools/mir5/replay.py"
PRIVATE_LUA_RUNTIME = ROOT / "build/tmp/mir421-lua-runtime"
LuaRuntime = None
SPEC = importlib.util.spec_from_file_location("mir5_replay", REPLAY_PATH)
assert SPEC and SPEC.loader
replay = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(replay)


def _load_lua_runtime(runtime_directory: Path):
    runtime = runtime_directory.resolve()
    if not runtime.is_dir():
        raise RuntimeError(f"Lua 5.2 runtime directory is absent: {runtime}")
    sys.path.insert(0, str(runtime))
    try:
        from lupa.lua52 import LuaRuntime as lua_runtime
    except ImportError as error:
        raise RuntimeError(f"Lua 5.2 runtime is unavailable from: {runtime}") from error
    return lua_runtime


def _require_lua_runtime():
    if LuaRuntime is None:
        raise RuntimeError(
            "Lua 5.2 execution is required; run with --lua-runtime-dir or use the private default"
        )
    return LuaRuntime


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _file_record(root: Path, path: Path) -> dict:
    return {"path": path.relative_to(root).as_posix(), "sha256": _sha(path), "bytes": path.stat().st_size}


def _base_raw() -> dict:
    return {
        "technology": {
            "existing": {
                "type": "technology", "name": "existing",
                "unit": {"count": 1, "ingredients": [["automation-science-pack", 1]]},
                "effects": [],
            }
        },
        "recipe": {
            "base": {"type": "recipe", "name": "base", "enabled": True, "ingredients": [["iron-plate", 1]]}
        },
    }


def _published_raw() -> dict:
    raw = _base_raw()
    raw["technology"]["existing"]["unit"]["count"] = 2
    raw["recipe"]["base"]["enabled"] = False
    raw["technology"]["new-research"] = {
        "type": "technology", "name": "new-research", "prerequisites": ["existing"],
        "unit": {"count": 3, "ingredients": [["automation-science-pack", 1]]},
        "localised_name": ["technology-name.new", "snowman ☃"],
        "effects": [],
    }
    raw["mod-data"] = {
        "mir-diagnostic": {
            "type": "mod-data", "name": "mir-diagnostic", "data_type": "synthetic",
            "data": {"tuple": ["one", 2], "override": {"enabled": True}},
        }
    }
    raw["bool-setting"] = {
        "mir-setting": {
            "type": "bool-setting", "name": "mir-setting", "setting_type": "startup", "default_value": True
        }
    }
    return raw


def _base_settings() -> dict:
    return {
        "bool-setting": {
            "shared-setting": {
                "type": "bool-setting", "name": "shared-setting", "setting_type": "startup", "default_value": True
            }
        }
    }


def _published_settings() -> dict:
    settings = _base_settings()
    settings["bool-setting"]["shared-setting"]["default_value"] = False
    settings["bool-setting"]["mir-setting"] = {
        "type": "bool-setting", "name": "mir-setting", "setting_type": "startup", "default_value": True
    }
    return settings


def _capture(root: Path, raw: dict, settings: dict, *, published: bool, base_version: str = "2.1.23") -> Path:
    root.mkdir()
    external = root.parent / "external"
    external.mkdir(exist_ok=True)
    engine_path = external / "factorio.exe"
    base_path = external / "base-info.json"
    harness_path = external / "capture-harness.ps1"
    profile_path = external / ("published-profile.json" if published else "no-mir-profile.json")
    for path, content in {
        engine_path: b"synthetic engine bytes",
        base_path: b'{"name":"base"}\n',
        harness_path: b"synthetic capture harness\n",
        profile_path: (b'{"mods":["base","more-infinite-research"]}\n' if published else b'{"mods":["base"]}\n'),
    }.items():
        if not path.exists():
            path.write_bytes(content)
    mir_path = external / "more-infinite-research_4.7.21000.zip"
    if published and not mir_path.exists():
        mir_path.write_bytes(b"synthetic published mir archive")
    data_path = root / "data-raw-dump.json"
    settings_path = root / "mod-settings-dump.json"
    selection_path = root / "selection.json"
    _write_json(data_path, raw)
    _write_json(settings_path, settings)
    mods = [{"name": "base", "version": base_version, "enabled": True}]
    if published:
        mods.append({"name": "more-infinite-research", "version": "4.7.21000", "enabled": True})
    _write_json(selection_path, {"mods": mods})
    selected = [{"name": "base", "version": base_version, "builtin": True, "path": str(base_path), "sha256": _sha(base_path)}]
    if published:
        selected.append({"name": "more-infinite-research", "version": "4.7.21000", "builtin": False,
                         "path": str(mir_path), "sha256": _sha(mir_path)})
    result = {
        "status": "completed-data-stage-observation-only",
        "process": {"passed": True, "timed_out": False, "exit_code": 0},
        "engine": {"path": str(engine_path), "sha256": _sha(engine_path), "base_version": base_version, "factorio_version": "2.1"},
        "profile_input": {"path": str(profile_path), "sha256": _sha(profile_path)},
        "harness": {"path": str(harness_path), "sha256": _sha(harness_path)},
        "mir_archive": ({"path": str(mir_path), "sha256": _sha(mir_path), "name": "more-infinite-research", "version": "4.7.21000"}
                        if published else None),
        "generated_selection": {**_file_record(root, selection_path), "mods": mods},
        "selected_archives": selected,
        "loaded_selection": [f"base@{base_version}"] + (["more-infinite-research@4.7.21000"] if published else []),
        "dumps": {"data_raw": _file_record(root, data_path), "mod_settings": _file_record(root, settings_path)},
    }
    _write_json(root / "result.json", result)
    return root


class ReplayTests(unittest.TestCase):
    def _pair(self, directory: Path, *, base_version: str = "2.1.23") -> tuple[Path, Path]:
        no_mir = _capture(directory / "no-mir", _base_raw(), _base_settings(), published=False, base_version=base_version)
        published = _capture(directory / "published", _published_raw(), _published_settings(), published=True, base_version=base_version)
        return no_mir, published

    def test_builds_full_unfiltered_data_and_settings_diagnostic_reference(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            receipt = replay.build_replay(no_mir, published, root / "output")
            output = root / "output"
            self.assertEqual(receipt["status"], "generated-offline-diagnostic-not-native-evidence")
            self.assertTrue(receipt["profile_specific"])
            self.assertEqual(receipt["comparison"], {
                "data_additions": 2, "data_patches": 2,
                "settings_additions": 1, "settings_patches": 1,
                "whole_prototype_deletions": 0, "unfiltered_prototype_types": True,
            })
            data = (output / "data-final-fixes.lua").read_text(encoding="utf-8")
            settings = (output / "settings.lua").read_text(encoding="utf-8")
            self.assertIn('local prototype = data.raw["technology"]["existing"]', data)
            self.assertIn('prototype["unit"]["count"] = 2', data)
            self.assertIn('local prototype = data.raw["recipe"]["base"]', data)
            self.assertIn('prototype["enabled"] = false', data)
            self.assertIn('"mod-data"', data)
            self.assertIn('\\226\\152\\131', data)
            self.assertIn('local prototype = data.raw["bool-setting"]["shared-setting"]', settings)
            self.assertIn('prototype["default_value"] = false', settings)
            self.assertIn('"mir-setting"', settings)
            for entrypoint in replay.EMPTY_ENTRYPOINTS:
                content = (output / entrypoint).read_text(encoding="utf-8")
                self.assertIn("Deliberately empty", content)
                self.assertNotIn("require", content)
            inventory = json.loads((output / "hash-inventory.json").read_text(encoding="utf-8"))
            self.assertEqual(len(inventory["inputs"]), 18)
            self.assertEqual({item["path"] for item in inventory["outputs"]}, {
                "data-final-fixes.lua", "settings.lua", "data.lua", "data-updates.lua",
                "settings-updates.lua", "settings-final-fixes.lua", "comparison-receipt.json",
            })

            lua = _require_lua_runtime()(unpack_returned_tuples=True)
            lua.execute('''
              data = {raw = {
                technology = {existing = {unit = {count = 1}}},
                recipe = {base = {enabled = true}},
                ["bool-setting"] = { ["shared-setting"] = {default_value = true} }
              }}
              function data:extend(prototypes)
                for _, prototype in ipairs(prototypes) do
                  self.raw[prototype.type] = self.raw[prototype.type] or {}
                  self.raw[prototype.type][prototype.name] = prototype
                end
              end
            ''')
            lua.globals().data_replay = data
            lua.globals().settings_replay = settings
            lua.execute('assert(load(data_replay))()\nassert(load(settings_replay))()')
            self.assertEqual(lua.globals().data.raw.technology["existing"].unit.count, 2)
            self.assertFalse(lua.globals().data.raw.recipe["base"].enabled)
            self.assertTrue(lua.globals().data.raw.technology["new-research"])
            self.assertFalse(lua.globals().data.raw["bool-setting"]["shared-setting"].default_value)

    def test_executes_more_than_two_hundred_patches_with_scoped_lua_locals(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            before = _base_raw()
            after = deepcopy(before)
            expected = {}
            for index in range(205):
                name = f"patched-{index:03d}"
                before["technology"][name] = {
                    "type": "technology", "name": name, "marker": 0,
                }
                after["technology"][name] = {
                    "type": "technology", "name": name, "marker": index + 1,
                }
                expected[name] = index + 1
            no_mir = _capture(root / "no-mir", before, _base_settings(), published=False)
            published = _capture(root / "published", after, _base_settings(), published=True)
            receipt = replay.build_replay(no_mir, published, root / "output")
            rendered = (root / "output" / "data-final-fixes.lua").read_text(encoding="utf-8")
            self.assertEqual(receipt["comparison"]["data_patches"], 205)
            self.assertEqual(rendered.count("local prototype = "), 205)
            self.assertEqual(rendered.count("\ndo\n"), 205)

            lua = _require_lua_runtime()(unpack_returned_tuples=True)
            lua.execute("data = {raw = " + replay.lua_value(before) + "}")
            lua.globals().data_replay = rendered
            lua.execute("assert(load(data_replay))()")
            for name, marker in expected.items():
                self.assertEqual(lua.globals().data.raw.technology[name].marker, marker)

    def test_serializer_is_deterministic_utf8_safe_and_rejects_cycles_or_nonfinite_values(self):
        first = replay.lua_value({"z": ["é", 2], "a": ("x", True)})
        second = replay.lua_value({"a": ("x", True), "z": ["é", 2]})
        self.assertEqual(first, second)
        self.assertIn('\\195\\169', first)
        self.assertIn('[1] = "x"', first)
        cyclic = {}
        cyclic["self"] = cyclic
        with self.assertRaisesRegex(replay.ReplayError, "cycle"):
            replay.lua_value(cyclic)
        with self.assertRaisesRegex(replay.ReplayError, "nonfinite"):
            replay.lua_value(float("inf"))
        with self.assertRaisesRegex(replay.ReplayError, "cannot contain JSON null"):
            replay.lua_value([None])

    def test_rejects_mismatched_capture_hash_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            (no_mir / "data-raw-dump.json").write_text("{}\n", encoding="utf-8")
            output = root / "output"
            with self.assertRaisesRegex(replay.ReplayError, "hash differs"):
                replay.build_replay(no_mir, published, output)
            self.assertFalse(output.exists())

    def test_rejects_tampered_external_capture_input_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            profile = root / "external" / "no-mir-profile.json"
            profile.write_text('{"tampered":true}\n', encoding="utf-8")
            output = root / "output"
            with self.assertRaisesRegex(replay.ReplayError, "profile input hash differs"):
                replay.build_replay(no_mir, published, output)
            self.assertFalse(output.exists())

    def test_rejects_incomplete_capture_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            result_path = no_mir / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            result["process"]["exit_code"] = 1
            _write_json(result_path, result)
            output = root / "output"
            with self.assertRaisesRegex(replay.ReplayError, "natural zero-exit"):
                replay.build_replay(no_mir, published, output)
            self.assertFalse(output.exists())

    def test_rejects_engine_or_upstream_selection_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            result_path = published / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            result["engine"]["base_version"] = "2.1.24"
            _write_json(result_path, result)
            with self.assertRaisesRegex(replay.ReplayError, "capture engines differ"):
                replay.build_replay(no_mir, published, root / "output")

    def test_accepts_a_historical_single_loaded_selection_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            result_path = no_mir / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            result["loaded_selection"] = "base@2.1.23"
            _write_json(result_path, result)
            receipt = replay.build_replay(no_mir, published, root / "output")
            self.assertEqual(receipt["comparison"]["data_patches"], 2)

    def test_rejects_upstream_selection_mismatch_after_removing_mir(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            result_path = published / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            result["generated_selection"]["mods"][0]["version"] = "2.1.24"
            selection_path = published / "selection.json"
            selection = json.loads(selection_path.read_text(encoding="utf-8"))
            selection["mods"][0]["version"] = "2.1.24"
            _write_json(selection_path, selection)
            result["generated_selection"] = {**_file_record(published, selection_path), "mods": selection["mods"]}
            result["selected_archives"][0]["version"] = "2.1.24"
            result["loaded_selection"][0] = "base@2.1.24"
            _write_json(result_path, result)
            with self.assertRaisesRegex(replay.ReplayError, "generated upstream selections differ"):
                replay.build_replay(no_mir, published, root / "output")

    def test_rejects_unsupported_whole_prototype_deletion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            no_mir, published = self._pair(root)
            data_path = published / "data-raw-dump.json"
            raw = json.loads(data_path.read_text(encoding="utf-8"))
            del raw["recipe"]["base"]
            _write_json(data_path, raw)
            result_path = published / "result.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            result["dumps"]["data_raw"] = _file_record(published, data_path)
            _write_json(result_path, result)
            with self.assertRaisesRegex(replay.ReplayError, "whole-prototype deletions"):
                replay.build_replay(no_mir, published, root / "output")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, default=PRIVATE_LUA_RUNTIME)
    args, unittest_args = parser.parse_known_args()
    LuaRuntime = _load_lua_runtime(args.lua_runtime_dir)
    unittest.main(argv=[sys.argv[0], *unittest_args], verbosity=2)
