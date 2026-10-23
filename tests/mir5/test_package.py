"""Package boundary and reproducibility checks independent of research output."""
import importlib.util
import hashlib
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mir_native_package", ROOT / "tools/mir5/package.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class PackageTests(unittest.TestCase):
    def test_selected_editions_have_one_actual_import_closure_and_exact_codec(self):
        source = ROOT / "source/mir5"
        for target, family, minimum in [
            ("f013", "0.13", "0.13.20"), ("f014", "0.14", "0.14.23"),
            ("f015", "0.15", "0.15.40"), ("f016", "0.16", "0.16.51"),
            ("f017", "0.17", "0.17.79"), ("f100", "1.0", "1.0.0"),
            ("f110", "1.1", "1.1.110"), ("f210", "2.1", "2.1.23"),
        ]:
            with self.subTest(target=target):
                info, rows = pack.members(source, target=target)
                files = dict(rows)
                self.assertEqual(info["factorio_version"], family)
                self.assertEqual(info["dependencies"], ["base >= " + minimum])
                self.assertEqual(info["version"], "5.0." + target[1:] + "00")
                self.assertEqual(json.loads(files["info.json"])["version"], info["version"])
                self.assertIn(('id = "' + target + '"').encode(), files["platform/target.lua"])
                reduced = target != "f210"
                self.assertEqual("research/historical_direct.lua" in files, reduced)
                self.assertEqual("runtime/bootstrap.lua" in files, not reduced)
                self.assertEqual("research/modern.lua" in files, not reduced)
                self.assertEqual(any(path.startswith("adapters/") for path in files), reduced)
                self.assertIn("api/v1/data.lua", files)
                self.assertIn("api/v1/runtime.lua", files)
                for migration in ("2.0.5", "2.1.0", "4.7.0"):
                    path = "migrations/more-infinite-research_" + migration + ".json"
                    self.assertIn(path, files)
                    self.assertEqual(files[path], (source / path).read_bytes())
                for name in files:
                    self.assertFalse(name.startswith(("source/", "targets/", "tests/", "spec/")))

    def test_unimplemented_unknown_and_arbitrary_edition_versions_refuse_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            for target in ("f200", "f018", "../f210"):
                output = Path(temporary) / target.replace("/", "_") / "more-infinite-research_5.0.20000.zip"
                with self.assertRaises(ValueError):
                    pack.build(ROOT / "source/mir5", output, target=target)
                self.assertFalse(output.exists())
                self.assertFalse(output.parent.exists())
            with self.assertRaises(ValueError):
                pack.members(ROOT / "source/mir5", version="5.0.01501", target="f015")

    def test_selected_edition_missing_module_refuses_instead_of_shipping_broken_imports(self):
        source = ROOT / "source/mir5"
        _, rows = pack.members(source)
        files = dict(rows)
        del files["adapters/reduced/control.lua"]
        with self.assertRaisesRegex(ValueError, "missing source dependency"):
            pack.members(source, committed_files=files, target="f015")

    def test_committed_target_record_is_frozen_with_the_player_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(["git", "-C", str(root), *arguments])
            git("init", "-q")
            git("config", "user.name", "Package test")
            git("config", "user.email", "package-test@example.invalid")
            source = root / "player"
            for name in [*pack.ENTRYPOINTS, "api/v1/data.lua", "api/v1/runtime.lua", "platform/target.lua"]:
                file = source / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("return {}\n")
            (source / "info.json").write_text(json.dumps({"name":"more-infinite-research",
                "version":"5.0.21000","factorio_version":"2.1","dependencies":["base >= 2.1.23"]}))
            edition = root / pack.TARGET_RECORD
            edition.parent.mkdir(parents=True)
            original = (ROOT / pack.TARGET_RECORD).read_bytes()
            edition.write_bytes(original)
            git("add", ".")
            git("commit", "-qm", "frozen player and edition")
            commit = git("rev-parse", "HEAD").decode().strip()
            edition.write_text('{"schema":1,"targets":{}}\n')
            record = pack.build(source, root / "out/more-infinite-research_5.0.21000.zip",
                                revision=commit, target="f210")
            self.assertEqual(record["edition_record_sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(record["source_commit"], commit)
            self.assertEqual(record["target"], "f210")
            with zipfile.ZipFile(record["archive"]) as archive:
                info = json.loads(archive.read("more-infinite-research_5.0.21000/info.json"))
                self.assertEqual(info["dependencies"], ["base >= 2.1.23"])
            self.assertEqual(edition.read_text(), '{"schema":1,"targets":{}}\n')

    def test_committed_build_ignores_dirty_untracked_and_line_ending_worktree_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            def git(*arguments):
                return subprocess.check_output(["git", "-C", str(repository), *arguments])
            git("init", "-q")
            git("config", "user.name", "Package test")
            git("config", "user.email", "package-test@example.invalid")
            source = repository / "player"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_bytes(b"return 'committed'\n")
            git("add", ".")
            git("commit", "-qm", "fixture")
            commit = git("rev-parse", "HEAD").decode().strip()
            (source / "data.lua").write_bytes(b"error('dirty')\r\n")
            (source / "new.lua").write_text("error('untracked')")
            output = repository / "package/test-fixture_0.1.0.zip"
            record = pack.build(source, output, revision=commit)
            self.assertEqual(record["source_commit"], commit)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.read("test-fixture_0.1.0/data.lua"), b"return 'committed'\n")
                self.assertNotIn("test-fixture_0.1.0/new.lua", archive.namelist())
            self.assertEqual((source / "data.lua").read_bytes(), b"error('dirty')\r\n")
            self.assertTrue((source / "new.lua").is_file())
            with self.assertRaises(ValueError):
                pack.build(repository, repository / "invalid/test-fixture_0.1.0.zip", revision=commit)

    def test_reproducible_members_and_fixture_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "source"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_text("data:extend({})\n")
            (source / "README.md").write_text("developer instructions")
            (source / "tests").mkdir()
            (source / "tests/leak.lua").write_text("error('developer-only')")
            first = directory / "one/test-fixture_0.2.0.zip"
            second = directory / "two/test-fixture_0.2.0.zip"
            a = pack.build(source, first, "0.2.0")
            b = pack.build(source, second, "0.2.0")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(a["sha256"], b["sha256"])
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), ["test-fixture_0.2.0/data.lua", "test-fixture_0.2.0/info.json"])
                self.assertEqual(json.loads(archive.read("test-fixture_0.2.0/info.json"))["version"], "0.2.0")
            self.assertEqual(json.loads((source / "info.json").read_text())["version"], "0.1.0")
            with self.assertRaises(FileExistsError):
                pack.build(source, first, "0.2.0")

    def test_only_top_level_migration_json_is_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            (source / "migrations" / "nested").mkdir(parents=True)
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            (source / "data.lua").write_text("data:extend({})\n")
            (source / "migrations" / "more-infinite-research_4.7.0.json").write_bytes(b'{"technology": []}\n')
            (source / "migrations" / "nested" / "not-a-factorio-migration.json").write_text("{}\n")
            (source / "unrelated.json").write_text("{}\n")
            output = root / "package/test-fixture_0.1.0.zip"
            pack.build(source, output)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
            self.assertIn("test-fixture_0.1.0/migrations/more-infinite-research_4.7.0.json", names)
            self.assertNotIn("test-fixture_0.1.0/migrations/nested/not-a-factorio-migration.json", names)
            self.assertNotIn("test-fixture_0.1.0/unrelated.json", names)

    def test_archive_identity_mismatch_is_refused_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            source.mkdir()
            (source / "info.json").write_text(json.dumps({"name": "test-fixture", "version": "0.1.0"}))
            output = Path(temporary) / "wrong.zip"
            with self.assertRaises(ValueError):
                pack.build(source, output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
