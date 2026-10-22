"""Synthetic opposing controls; these do not execute Factorio."""
from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/mir5"))
import compare_captures as comparator
from test_replay import _capture, _published_raw, _published_settings, _sha, _write_json


class ComparisonTests(unittest.TestCase):
    def pair(self, root, raw=None, settings=None, **kwargs):
        left = _capture(root / "left", _published_raw(), _published_settings(), published=True)
        right = _capture(root / "right", raw if raw is not None else _published_raw(),
                         settings if settings is not None else _published_settings(), published=True, **kwargs)
        archive = root / "external/more-infinite-research_4.7.21000.zip"
        return left, right, archive

    def test_complete_equal_output_with_relocated_exact_custody_leaves_receipts_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left, right, archive = self.pair(root)
            retained = root / "retained.zip"
            retained.write_bytes(archive.read_bytes())
            archive.write_bytes(b"different live library selection")
            originals = [(path / "result.json").read_bytes() for path in (left, right)]
            result = comparator.compare(left, right, retained, retained)
            self.assertEqual(result["status"], "equal-complete-native-output")
            self.assertEqual(result["differences"], [])
            self.assertEqual(originals, [(path / "result.json").read_bytes() for path in (left, right)])
            with self.assertRaisesRegex(comparator.replay.ReplayError, "hash differs"):
                comparator.compare(left, right, retained, archive)

    def test_unrelated_recipe_and_boolean_number_changes_are_detected(self):
        for changed_domain in ("recipe", "settings"):
            with self.subTest(domain=changed_domain), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                raw, settings = _published_raw(), _published_settings()
                if changed_domain == "recipe":
                    raw["recipe"]["base"]["ingredients"][0][1] = 2
                else:
                    settings["bool-setting"]["mir-setting"]["default_value"] = 1
                left, right, archive = self.pair(root, raw, settings)
                result = comparator.compare(left, right, archive, archive)
                self.assertEqual(result["status"], "different-native-output")
                self.assertEqual(len(result["differences"]), 1)

    def test_engine_mismatch_and_tampered_dump_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left, right, archive = self.pair(root, base_version="2.1.24")
            with self.assertRaisesRegex(comparator.replay.ReplayError, "engines differ"):
                comparator.compare(left, right, archive, archive)
            (right / "data-raw-dump.json").write_text("{}", encoding="utf-8")
            with self.assertRaisesRegex(comparator.replay.ReplayError, "hash differs"):
                comparator.compare(left, right, archive, archive)

    def test_selected_mir_hash_cannot_be_replaced_by_custody_override(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left, right, archive = self.pair(root)
            path = right / "result.json"
            receipt = json.loads(path.read_text())
            for selected in receipt["selected_archives"]:
                if selected["name"] == "more-infinite-research":
                    selected["sha256"] = "0" * 64
            _write_json(path, receipt)
            with self.assertRaisesRegex(comparator.replay.ReplayError, "MIR archive differs"):
                comparator.compare(left, right, archive, archive)


if __name__ == "__main__":
    unittest.main()
