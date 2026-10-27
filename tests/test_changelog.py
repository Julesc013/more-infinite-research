"""Master history custody and the generated Factorio formatting boundary."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("changelog", ROOT / "tools/changelog.py")
changelog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(changelog)
MASTERS = "1.0.0 1.1.0 1.1.5 1.2.0 1.2.5 1.2.9 2.0.0 2.0.5 2.1.0 2.1.5 2.2.0 2.3.0 3.0.0 3.0.5 3.1.0 3.1.1 3.1.2 3.1.5 3.1.9 3.2.0 3.2.1 3.2.2 3.2.3 3.2.5 3.2.9 3.2.10 3.2.11".split()


class ChangelogTests(unittest.TestCase):
    def test_all_selected_master_entries_retain_the_recovered_full_text(self):
        records = {r["version"]: r for r in changelog.entries((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"))}
        inventory = json.loads((ROOT / "spec/inventory/changelog-history.json").read_bytes())
        self.assertEqual(inventory["master_mir1_3"]["selected_versions"], MASTERS)
        self.assertEqual({v for v in records if int(v.split(".")[0]) < 4}, set(MASTERS))
        for expected in inventory["master_mir1_3"]["entry_semantics"]:
            with self.subTest(version=expected["version"]):
                data = json.dumps(records[expected["version"]], sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
                self.assertEqual(hashlib.sha256(data).hexdigest().upper(), expected["sha256"])
        self.assertEqual({v for v in records if v.startswith("4.")}, set(inventory["mir4_source_versions"]))

    def test_replaced_edition_history_fingerprints_keep_published_custody(self):
        inventory = json.loads((ROOT / "spec/inventory/changelog-history.json").read_bytes())
        published = json.loads((ROOT / "spec/inventory/package-presentation-473.json").read_bytes())
        inputs = {row["target"]: row for row in inventory["prior_edition_histories"]}
        self.assertEqual(set(inputs), {row["target"] for row in published["records"]})
        for row in published["records"]:
            with self.subTest(target=row["target"]):
                self.assertEqual(inputs[row["target"]]["sha256"], row["history_sha256"])
                self.assertEqual(inputs[row["target"]]["bytes"], row["bytes"])

    def test_projection_is_current_bounded_and_only_current_version_is_substituted(self):
        output = changelog.rendered()
        self.assertEqual((ROOT / "source/changelog.txt").read_text(encoding="utf-8"), output)
        self.assertNotIn("@DISTRIBUTION_VERSION@", output)
        self.assertTrue(output.startswith(changelog.SEPARATOR + "\nVersion: 5.0.0\n"))
        self.assertLessEqual(max(map(len, output.splitlines())), 132)
        self.assertIn("\nVersion: 4.7.3\n", output)
        self.assertIn("\nVersion: 1.0.0\n", output)
        self.assertNotIn("Date: Unreleased", output)

    def test_formatting_keeps_words_nested_bullets_and_unknown_dates(self):
        text = "# Changelog\n\n## [5.0.1] - Unreleased\n\n### Changes\n\n- " + "long words " * 30 + "\n  - Child.\n\n## [5.0.0]\n\n### Fixes\n\n- Prior.\n"
        output = changelog.factorio(text, "5.0.1")
        self.assertIn("Child.", output)
        self.assertFalse(any(line.startswith("        ") for line in output.splitlines()))
        self.assertEqual(" ".join(output.split()).count("long words"), 30)
        self.assertNotIn("Date:", output)
        self.assertIn("Version: 5.0.0", output)

    def test_dropped_prose_duplicate_versions_wrong_version_and_hard_wrap_fail(self):
        base = "## [5.0.0] - Unreleased\n\n### Changes\n\n- One.\n"
        for bad in (base + "wrapped continuation\n", base + base, base + "  wrapped continuation\n", base.replace("- One.", "  - Orphan.")):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                changelog.factorio(bad, "5.0.0")
        with self.assertRaisesRegex(ValueError, "differs"):
            changelog.factorio(base, "5.0.1")

    def test_factorio_entries_and_continuations_are_unique_per_category(self):
        version = category = None
        seen = set()
        for line in changelog.rendered().splitlines():
            if line.startswith("Version: "):
                version = line
            elif line.startswith("  ") and not line.startswith("   "):
                category = line
                seen = set()
            elif line.startswith("    "):
                with self.subTest(version=version, category=category, line=line):
                    self.assertNotIn(line, seen)
                    self.assertTrue(line.startswith("    - ") or (line.startswith("      ") and not line.startswith("       ")))
                seen.add(line)


if __name__ == "__main__":
    unittest.main()
