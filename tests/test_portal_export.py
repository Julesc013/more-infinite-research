"""Final Portal-copy boundary controls independent of player-source packaging."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mir_portal_export", ROOT / "tools/export_portal.py")
portal = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(portal)


class PortalExportTests(unittest.TestCase):
    @staticmethod
    def _sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest().upper()

    @staticmethod
    def _extended_version(target: str, source_patch=0) -> str:
        return "5.0." + str(int(target[1:]) * 100 + source_patch).zfill(5)

    @classmethod
    def _write_completed_zip(cls, path: Path, target="f210", source_patch=0, *, root=None,
                             info_version=None, member_overrides=None, extra_members=()):
        extended = cls._extended_version(target, source_patch)
        root = root or "more-infinite-research_" + extended
        info_version = info_version or extended
        members = [
            (root + "/info.json", (json.dumps({
                "name": "more-infinite-research", "version": info_version,
                "factorio_version": "2.1", "description": "retained package metadata",
            }, ensure_ascii=False, indent=2) + "\n").encode("utf-8")),
            (root + "/platform/target.lua", (
                "return {\n"
                "  id = \"" + target + "\",\n"
                "  distribution_version = \"" + extended + "\",\n"
                "  retained = \"all other target data stays byte-identical\",\n"
                "}\n").encode("utf-8")),
            (root + "/changelog.txt", b"-----------------------------------------------------------------------------------\nVersion: 5.0.0\n"),
            (root + "/migrations/more-infinite-research_5.0.11000.json", b'{"retained":true}\n'),
            (root + "/graphics/retained.bin", b"\x00retained player bytes\xff"),
        ]
        member_overrides = member_overrides or {}
        members = [(name, member_overrides.get(name, payload)) for name, payload in members]
        members.extend(extra_members)
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            archive.comment = b"completed extended package comment"
            for name, payload in members:
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr(entry, payload, compresslevel=9)
        return extended, root

    @staticmethod
    def _members(path: Path):
        with zipfile.ZipFile(path) as archive:
            return archive.namelist(), {entry.filename: archive.read(entry) for entry in archive.infolist()}, archive.comment

    def test_final_copy_changes_only_two_member_payloads_and_preserves_completed_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            input_archive = temporary / "more-infinite-research_5.0.21000.zip"
            extended, root = self._write_completed_zip(input_archive)
            before_bytes = input_archive.read_bytes()
            names, payloads, comment = self._members(input_archive)
            output = temporary / "more-infinite-research_5.0.09.zip"

            record = portal.export_portal_copy(input_archive, "f210", output)

            output_names, output_payloads, output_comment = self._members(output)
            info_path, target_path = root + "/info.json", root + "/platform/target.lua"
            self.assertEqual(names, output_names)
            self.assertEqual(comment, output_comment)
            self.assertEqual(before_bytes, input_archive.read_bytes())
            self.assertEqual(json.loads(output_payloads[info_path])["version"], "5.0.09")
            self.assertIn(b'distribution_version = "5.0.09"', output_payloads[target_path])
            self.assertEqual(payloads[info_path].replace(extended.encode(), b"5.0.09", 1), output_payloads[info_path])
            self.assertEqual(payloads[target_path].replace(extended.encode(), b"5.0.09", 1), output_payloads[target_path])
            for path, payload in payloads.items():
                if path not in {info_path, target_path}:
                    self.assertEqual(payload, output_payloads[path])
            self.assertEqual(record["status"], "exported-not-release-qualified")
            self.assertEqual(record["extended_version"], extended)
            self.assertEqual(record["portal_version"], "5.0.09")
            self.assertEqual(record["input"]["sha256"], self._sha256(input_archive))
            self.assertEqual(record["input"]["sha256_after_export"], self._sha256(input_archive))
            self.assertEqual(record["output"]["sha256"], self._sha256(output))
            self.assertEqual([row["path"] for row in record["permitted_member_differences"]], [info_path, target_path])

    def test_all_nine_stable_mappings_keep_the_source_patch_and_reject_experimental_f018(self):
        expected = {
            "f013": "5.0.01", "f014": "5.0.02", "f015": "5.0.03", "f016": "5.0.04", "f017": "5.0.05",
            "f100": "5.0.06", "f110": "5.0.07", "f200": "5.0.08", "f210": "5.0.09",
        }
        self.assertEqual({target: portal._portal_version(target, self._extended_version(target))
                          for target in expected}, expected)
        self.assertEqual(portal._portal_version("f013", "5.0.01399"), "5.0.991")
        self.assertEqual(portal._portal_version("f210", "5.0.21099"), "5.0.999")
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            input_archive = temporary / "more-infinite-research_5.0.01800.zip"
            self._write_completed_zip(input_archive, target="f018")
            with self.assertRaisesRegex(portal.PortalExportError, "nine stable editions"):
                portal.export_portal_copy(input_archive, "f018", temporary / "more-infinite-research_5.0.06.zip")

    def test_refuses_wrong_edition_root_version_filename_duplicate_and_path_anomalies(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            cases = {
                "wrong-edition": lambda path: (self._write_completed_zip(path), "f200", "different edition"),
                "wrong-root": lambda path: (self._write_completed_zip(path, root="more-infinite-research_5.0.20000"), "f210", "archive root"),
                "wrong-info": lambda path: (self._write_completed_zip(path, info_version="5.0.21001"), "f210", "info metadata"),
                "duplicate": lambda path: (self._write_completed_zip(path, extra_members=(("more-infinite-research_5.0.21000/info.json", b"{}"),)), "f210", "duplicate"),
                "path": lambda path: (self._write_completed_zip(path, extra_members=(("more-infinite-research_5.0.21000/../outside", b"no"),)), "f210", "invalid member path"),
            }
            for name, prepare in cases.items():
                with self.subTest(case=name):
                    case_directory = temporary / name
                    case_directory.mkdir()
                    input_archive = case_directory / "more-infinite-research_5.0.21000.zip"
                    _, target, expected_error = prepare(input_archive)
                    output = case_directory / "more-infinite-research_5.0.09.zip"
                    with self.assertRaisesRegex(portal.PortalExportError, expected_error):
                        portal.export_portal_copy(input_archive, target, output)

    def test_refuses_a_zip_whose_external_name_is_not_the_completed_extended_package_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            input_archive = temporary / "unlabelled-input.zip"
            self._write_completed_zip(input_archive)
            with self.assertRaisesRegex(portal.PortalExportError, "input filename"):
                portal.export_portal_copy(input_archive, "f210", temporary / "more-infinite-research_5.0.09.zip")

    def test_refuses_existing_output_and_cli_reports_its_own_copy_checksum(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            input_archive = temporary / "more-infinite-research_5.0.21000.zip"
            self._write_completed_zip(input_archive)
            output = temporary / "more-infinite-research_5.0.09.zip"
            output.write_bytes(b"preserve existing output")
            with self.assertRaises(FileExistsError):
                portal.export_portal_copy(input_archive, "f210", output)
            self.assertEqual(output.read_bytes(), b"preserve existing output")
            output.unlink()
            completed = subprocess.run(
                [sys.executable, str(ROOT / "tools/export_portal.py"), "--input", str(input_archive),
                 "--target", "f210", "--output", str(output)],
                cwd=ROOT, check=True, text=True, capture_output=True,
            )
            record = json.loads(completed.stdout)
            self.assertEqual(record["output"]["sha256"], self._sha256(output))
            self.assertEqual(record["output"]["path"], str(output.resolve()))

    def test_refuses_a_changed_input_after_writing_and_preserves_the_partial_copy_for_diagnosis(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            input_archive = temporary / "more-infinite-research_5.0.21000.zip"
            self._write_completed_zip(input_archive)
            original_input = input_archive.read_bytes()
            output = temporary / "more-infinite-research_5.0.09.zip"
            original_reader = portal._read_completed_archive

            def read_then_change_input(path, *arguments):
                result = original_reader(path, *arguments)
                if Path(path).resolve() == output.resolve():
                    input_archive.write_bytes(original_input + b"changed-after-copy")
                return result

            portal._read_completed_archive = read_then_change_input
            try:
                with self.assertRaisesRegex(portal.PortalExportError, "changed while the Portal copy was written"):
                    portal.export_portal_copy(input_archive, "f210", output)
            finally:
                portal._read_completed_archive = original_reader
            self.assertTrue(output.is_file())
            self.assertEqual(output.read_bytes()[:2], b"PK")


if __name__ == "__main__":
    unittest.main()
