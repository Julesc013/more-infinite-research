"""Independent source-release/target-codec expectations for test consumers."""
import json
from pathlib import Path
import tempfile
import unittest

from mir_test_versions import alias_for, current_alias, current_source_release, declared_targets


ROOT = Path(__file__).resolve().parents[1]


class VersionAliasTests(unittest.TestCase):
    # These independent vectors intentionally do not calculate values through
    # the helper under test or import the production package encoder.
    GOLDENS = {
        "5.0.0": {
            "f006": "5.0.00600", "f007": "5.0.00700", "f008": "5.0.00800",
            "f009": "5.0.00900", "f010": "5.0.01000", "f011": "5.0.01100",
            "f012": "5.0.01200", "f013": "5.0.01300", "f014": "5.0.01400",
            "f015": "5.0.01500", "f016": "5.0.01600", "f017": "5.0.01700",
            "f018": "5.0.01800", "f100": "5.0.10000", "f110": "5.0.11000",
            "f200": "5.0.20000", "f210": "5.0.21000",
        },
        "5.0.17": {
            "f006": "5.0.00617", "f007": "5.0.00717", "f008": "5.0.00817",
            "f009": "5.0.00917", "f010": "5.0.01017", "f011": "5.0.01117",
            "f012": "5.0.01217", "f013": "5.0.01317", "f014": "5.0.01417",
            "f015": "5.0.01517", "f016": "5.0.01617", "f017": "5.0.01717",
            "f018": "5.0.01817", "f100": "5.0.10017", "f110": "5.0.11017",
            "f200": "5.0.20017", "f210": "5.0.21017",
        },
        "5.0.99": {
            "f006": "5.0.00699", "f007": "5.0.00799", "f008": "5.0.00899",
            "f009": "5.0.00999", "f010": "5.0.01099", "f011": "5.0.01199",
            "f012": "5.0.01299", "f013": "5.0.01399", "f014": "5.0.01499",
            "f015": "5.0.01599", "f016": "5.0.01699", "f017": "5.0.01799",
            "f018": "5.0.01899", "f100": "5.0.10099", "f110": "5.0.11099",
            "f200": "5.0.20099", "f210": "5.0.21099",
        },
    }

    def test_all_declared_targets_have_independent_patch_zero_seventeen_and_ninety_nine_vectors(self):
        self.assertEqual(set(declared_targets()), set(self.GOLDENS["5.0.0"]))
        for source_release, expected in self.GOLDENS.items():
            for target, distribution in expected.items():
                with self.subTest(source_release=source_release, target=target):
                    self.assertEqual(alias_for(source_release, target).distribution_version, distribution)

    def test_fixed_release_has_explicit_python_lua_json_dependency_and_archive_forms(self):
        alias = alias_for("5.0.16", "f210")
        self.assertEqual(alias.distribution_version, "5.0.21016")
        self.assertEqual(alias.python_literal, "'5.0.21016'")
        self.assertEqual(alias.lua_literal, '"5.0.21016"')
        self.assertEqual(alias.json_literal, '"5.0.21016"')
        self.assertEqual(alias.dependency, "more-infinite-research = 5.0.21016")
        self.assertEqual(alias.archive_root, "more-infinite-research_5.0.21016")
        self.assertEqual(alias.archive_name, "more-infinite-research_5.0.21016.zip")
        self.assertEqual(alias.archive_path("archive-output"), Path("archive-output") / alias.archive_name)
        self.assertNotEqual(alias_for("5.0.16", "f200").distribution_version, alias.distribution_version)

    def test_current_release_reads_the_authored_changelog_not_player_or_package_output(self):
        expected = current_source_release()
        self.assertEqual(current_alias("f210").source_release, expected)
        self.assertEqual(current_alias("f210").distribution_version,
                         json.loads((ROOT / "source/info.json").read_text(encoding="utf-8"))["version"])
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            (fixture / "CHANGELOG.md").write_text(
                "# Changelog\n\n## [5.7.17] - 2026-11-16\n\n### Bugfixes\n\n- Test.\n",
                encoding="utf-8",
            )
            self.assertEqual(current_source_release(root=fixture), "5.7.17")

    def test_invalid_source_forms_and_targets_refuse_instead_of_rewriting_history(self):
        for source_release in (None, 5, "5.0", "5.0.001", "05.0.1", "5.00.1", "5.0.-1", "5.0.100",
                               "5.0.21016"):
            with self.subTest(source_release=source_release):
                with self.assertRaisesRegex(ValueError, "source release"):
                    alias_for(source_release, "f210")
        for target in (None, "", "F210", "f21", "f211", "../f210", "f210.zip"):
            with self.subTest(target=target):
                with self.assertRaisesRegex(ValueError, "target"):
                    alias_for("5.0.16", target)

    def test_malformed_current_changelog_heading_refuses_without_falling_back_to_history(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            (fixture / "CHANGELOG.md").write_text(
                "# Changelog\n\n## [5.0.016] - 2026-11-16\n\n## [5.0.15] - 2026-11-15\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "canonical current release"):
                current_source_release(root=fixture)


if __name__ == "__main__":
    unittest.main()
