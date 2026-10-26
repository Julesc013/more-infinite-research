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
                        changelog = archive.read(root + "/changelog.txt")
                        locale = archive.read(root + "/locale/en/more-infinite-research.cfg")
                    self.assertEqual(names, [
                        root + "/LICENSE",
                        root + "/adapters/early/data.lua",
                        root + "/adapters/early/definitions.lua",
                        root + "/changelog.txt",
                        root + "/data.lua",
                        root + "/info.json",
                        root + "/locale/en/more-infinite-research.cfg",
                        root + "/platform/target.lua",
                        root + "/research/generator.lua",
                        root + "/thumbnail.png",
                    ])
                    self.assertEqual(info, {
                        "name": "more-infinite-research",
                        "version": "5.0." + target[1:] + "00",
                        "title": "More Infinite Research",
                        "author": "Julesc013",
                        "description": pack.EARLY_DESCRIPTION,
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
                    self.assertNotIn(b"@DISTRIBUTION_VERSION@", changelog)
                    self.assertEqual(changelog.count(
                        b"Version: 5.0." + target[1:].encode("ascii") + b"00"), 1)
                    self.assertEqual(locale, (source / pack.EARLY_LOCALE_SOURCE).read_bytes())
                    self.assertIn(
                        ("mir-" + {
                            "f006": "rocket-damage-1",
                            "f012": "logistic-trash-slots-1",
                        }.get(target, "gun-turret-damage-1") + "=").encode("ascii"),
                        locale,
                    )
                    self.assertFalse(any(any(token in name for token in (
                        "/settings.lua", "/control.lua", "/data-final-fixes.lua", "/migrations/", "/runtime/", "/api/",
                        "/presentation/", "/CHANGELOG.md", "/tools/", "/adapters/early/locale/"
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

    def test_missing_early_adapter_or_locale_refuses_before_output(self):
        for relative, message in (
            ("adapters/early/definitions.lua", "missing source dependency"),
            (pack.EARLY_LOCALE_SOURCE, "missing player asset"),
        ):
            with self.subTest(relative=relative), self._early_repository() as (repository, source, _):
                (source / relative).unlink()
                self._git(repository, "add", "-A")
                self._git(repository, "commit", "-qm", "remove early package input")
                revision = self._git(repository, "rev-parse", "HEAD").decode().strip()
                output = repository / ("missing-" + Path(relative).name + ".zip")
                with self.assertRaisesRegex(ValueError, message):
                    pack.build(source, output, revision=revision, target="f006", target_record=EARLY_RECORD)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
