"""Tier 0 boundaries for the current MIR 5 player source tree."""
import importlib.util
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
PLAYER = ROOT / "source/mir5"
IMPORT = re.compile(r"require\s*\(\s*[\"']([^\"']+)[\"']\s*\)")
PACKAGE_PREFIX = "__more-infinite-research__/"


def load_module(name, relative):
    specification = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


package = load_module("mir5_package_under_test", "tools/mir5/package.py")


def imports(path):
    return IMPORT.findall(path.read_text(encoding="utf-8"))


def local_module(target):
    if target.startswith(PACKAGE_PREFIX):
        target = target[len(PACKAGE_PREFIX):].replace("/", ".")
    return PLAYER / (target.replace(".", "/") + ".lua")


def local_closure(roots):
    pending = list(roots)
    seen = set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        for target in imports(path):
            candidate = local_module(target)
            if not candidate.is_file():
                raise AssertionError(f"player import is outside the MIR 5 root: {target}")
            pending.append(candidate)
    return seen


class PackTests(unittest.TestCase):
    def test_frozen_import_custody_metadata_remains_well_formed(self):
        current = json.loads((ROOT / "tools/mir5/adoption/pack_members.json").read_text(encoding="utf-8"))
        frozen = json.loads((ROOT / "tools/mir5/adoption/base_members.json").read_text(encoding="utf-8"))
        self.assertEqual(current["format"], 1)
        self.assertEqual(frozen["format"], 1)
        self.assertEqual(frozen["purpose"], "preimages-of-user-uploaded-pack-not-live-repo-authority")
        self.assertEqual(len(current["files"]), len(set(current["files"])))
        self.assertTrue(all((ROOT / path).is_file() for path in current["files"]))
        self.assertIn("tools/mir5/adoption/base_members.json", current["files"])
        self.assertIn("tools/mir5/adoption/pack_members.json", current["files"])
        self.assertGreater(len(frozen["files"]), 0)
        for path, digest in frozen["files"].items():
            self.assertRegex(path, r"^(?!/)(?!.*(?:^|/)\.\.(?:/|$)).+")
            self.assertRegex(digest, r"^[0-9a-f]{64}$")

    def test_player_package_admits_only_native_files_and_all_locale_assets(self):
        _, members = package.members(PLAYER)
        admitted = {path for path, _ in members}
        expected = {"info.json"}
        expected.update(
            name for name in {"LICENSE", "LICENSE.txt", "changelog.txt"}
            if (PLAYER / name).is_file()
        )
        expected.update(path.relative_to(PLAYER).as_posix() for path in PLAYER.rglob("*.lua"))
        expected.update(path.relative_to(PLAYER).as_posix() for path in (PLAYER / "locale").rglob("*.cfg"))
        graphics = PLAYER / "graphics"
        if graphics.is_dir():
            expected.update(
                path.relative_to(PLAYER).as_posix()
                for path in graphics.rglob("*")
                if path.is_file() and path.suffix.lower() in {".png", ".jpg", ".ogg"}
            )
        self.assertEqual(admitted, expected)
        self.assertIn("locale/en/more-infinite-research.cfg", admitted)
        self.assertNotIn("README.md", admitted)
        standalone = {"info.json", "LICENSE", "LICENSE.txt", "changelog.txt"}
        self.assertTrue(
            all(path in standalone or path.endswith((".lua", ".cfg", ".png", ".jpg", ".ogg")) for path in admitted)
        )

    def test_settings_stage_closure_is_data_only(self):
        closure = local_closure([PLAYER / "settings.lua"])
        self.assertEqual(
            {path.relative_to(PLAYER).as_posix() for path in closure},
            {"settings.lua", "research/settings.lua", "research/settings_profile.lua"},
        )
        self.assertNotIn(PLAYER / "research/generator.lua", closure)
        self.assertFalse(any("runtime" in path.parts or "api" in path.parts for path in closure))

    def test_runtime_closure_never_imports_the_generator(self):
        closure = local_closure([PLAYER / "control.lua", PLAYER / "api/v1/runtime.lua"])
        relative = {path.relative_to(PLAYER).as_posix() for path in closure}
        self.assertIn("runtime/lifecycle.lua", relative)
        self.assertIn("runtime/caps.lua", relative)
        self.assertNotIn("research/generator.lua", relative)
        self.assertNotIn("api/v1/data.lua", relative)

    def test_player_imports_cannot_route_to_mir4(self):
        for path in PLAYER.rglob("*.lua"):
            for target in imports(path):
                lowered = target.lower()
                self.assertNotIn("mir4", lowered, f"{path}: {target}")
                self.assertNotRegex(lowered, r"(?:^|[./])(?:src|prototypes)(?:[./]|$)", f"{path}: {target}")
                self.assertTrue(local_module(target).is_file(), f"{path}: {target}")

    def test_player_identity_is_private_and_not_a_native_claim(self):
        info = json.loads((PLAYER / "info.json").read_text(encoding="utf-8"))
        self.assertEqual(info["name"], "more-infinite-research")
        self.assertEqual(info["factorio_version"], "2.1")
        self.assertIn("Incomplete", info["description"])
        self.assertIn("disposable test worlds", (PLAYER / "README.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
