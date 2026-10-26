"""Opt-in F006--F012 data-only package boundary checks."""
import importlib.util
import contextlib
import json
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
EARLY_RECORD = "targets/early-editions.json"
spec = importlib.util.spec_from_file_location("mir_native_package", ROOT / "tools/package.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class EarlyPackageTests(unittest.TestCase):
    @staticmethod
    def _git(repository, *arguments):
        return subprocess.check_output(["git", "-C", str(repository), *arguments])

    @contextlib.contextmanager
    def _early_repository(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            source = repository / "source"
            shutil.copytree(ROOT / "source", source)
            adapter = source / "adapters/early/data.lua"
            if not adapter.exists():
                adapter.parent.mkdir(parents=True, exist_ok=True)
                (adapter.parent / "definitions.lua").write_text("return {}\n", encoding="utf-8")
                generator = source / "research/generator.lua"
                generator.parent.mkdir(parents=True, exist_ok=True)
                generator.write_text("return {}\n", encoding="utf-8")
                adapter.write_text(
                    "local definitions = require(\"adapters.early.definitions\")\n"
                    "local generator = require(\"research.generator\")\n"
                    "local M = {}\n"
                    "function M.apply(target)\n"
                    "  assert(target.id and target.reduced == true and target.research_levels == false and target.recipe_productivity == false)\n"
                    "  data:extend({})\n"
                    "end\n"
                    "return M\n",
                    encoding="utf-8",
                )
            record = repository / EARLY_RECORD
            record.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / EARLY_RECORD, record)
            shutil.copyfile(ROOT / pack.TARGET_RECORD, repository / pack.TARGET_RECORD)
            self._git(repository, "init", "-q")
            self._git(repository, "config", "user.name", "Early package test")
            self._git(repository, "config", "user.email", "early-package-test@example.invalid")
            self._git(repository, "config", "core.autocrlf", "false")
            self._git(repository, "add", ".")
            self._git(repository, "commit", "-qm", "early package source")
            yield repository, source, self._git(repository, "rev-parse", "HEAD").decode().strip()

    def test_opt_in_early_records_emit_only_the_data_adapter_closure(self):
        early = json.loads((ROOT / EARLY_RECORD).read_text(encoding="utf-8"))
        self.assertEqual(early["schema"], 1)
        self.assertEqual(
            early["qualification"],
            "best-effort-early-data-only-distributions-not-native-qualified",
        )
        self.assertEqual(set(early["targets"]), {"f006", "f007", "f008", "f009", "f010", "f011", "f012"})
        with self._early_repository() as (repository, source, revision):
            for target, selected in early["targets"].items():
                with self.subTest(target=target):
                    # This deliberately does not use the normal player-root
                    # filename: early zip-loader/root rules are unqualified.
                    output = repository / "out" / (target + "-transport.bundle")
                    record = pack.build(
                        source,
                        output,
                        revision=revision,
                        target=target,
                        target_record=EARLY_RECORD,
                    )
                    root = "more-infinite-research_5.0." + target[1:] + "00"
                    self.assertEqual(record["kind"], "early-data-only-package-members-not-gameplay-qualification")
                    self.assertEqual(record["delivery"], selected["delivery"])
                    self.assertEqual(record["target_record"], EARLY_RECORD)
                    self.assertEqual(record["version"], "5.0." + target[1:] + "00")
                    with zipfile.ZipFile(output) as archive:
                        names = archive.namelist()
                        info = json.loads(archive.read(root + "/info.json"))
                        target_lua = archive.read(root + "/platform/target.lua")
                        entrypoint = archive.read(root + "/data.lua")
                    self.assertEqual(names, [
                        root + "/LICENSE",
                        root + "/adapters/early/data.lua",
                        root + "/adapters/early/definitions.lua",
                        root + "/data.lua",
                        root + "/info.json",
                        root + "/platform/target.lua",
                        root + "/research/generator.lua",
                    ])
                    self.assertEqual(info, {
                        "name": "more-infinite-research",
                        "version": "5.0." + target[1:] + "00",
                        "factorio_version": selected["factorio_version"],
                        "dependencies": ["base >= " + selected["minimum_base"]],
                    })
                    self.assertEqual(target_lua, (
                        b"-- Selected early data-only target; native qualification is held outside player source.\n"
                        b"return {\n"
                        + ("  id = %r,\n" % target).replace("'", '"').encode("ascii")
                        + b"  reduced = true,\n"
                        + b"  research_levels = false,\n"
                        + b"  recipe_productivity = false\n"
                        + b"}\n"
                    ))
                    self.assertEqual(
                        entrypoint,
                        b'require("adapters.early.data").apply(require("platform.target"))\n',
                    )
                    self.assertFalse(any(any(token in name for token in (
                        "/settings.lua", "/control.lua", "/data-final-fixes.lua", "/migrations/", "/runtime/", "/api/"
                    )) for name in names))

    def test_early_selection_is_explicit_and_refuses_wrong_target_shapes_before_output(self):
        with self._early_repository() as (repository, source, revision):
            with self.assertRaisesRegex(ValueError, "Select a declared MIR player edition"):
                pack.build(source, repository / "default.zip", revision=revision, target="f006")
            self.assertFalse((repository / "default.zip").exists())

            for target in ("f001", "f005", "f013"):
                with self.subTest(target=target), self.assertRaisesRegex(ValueError, "early"):
                    pack.build(
                        source,
                        repository / ("wrong-" + target + ".zip"),
                        revision=revision,
                        target=target,
                        target_record=EARLY_RECORD,
                    )
                self.assertFalse((repository / ("wrong-" + target + ".zip")).exists())

            record = repository / EARLY_RECORD
            bad = json.loads(record.read_text(encoding="utf-8"))
            bad["targets"]["f006"]["factorio_version"] = "0.6"
            record.write_text(json.dumps(bad), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "target record differs from the frozen revision"):
                pack.build(
                    source,
                    repository / "dirty-record.zip",
                    revision=revision,
                    target="f006",
                    target_record=EARLY_RECORD,
                )
            self.assertFalse((repository / "dirty-record.zip").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
