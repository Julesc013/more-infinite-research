"""Package boundary and reproducibility checks independent of research output."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mir_native_package", ROOT / "tools/mir5/package.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class PackageTests(unittest.TestCase):
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
