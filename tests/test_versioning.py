"""Independent portal and extended distribution codec controls."""
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import versioning  # noqa: E402


class VersioningTests(unittest.TestCase):
    PORTAL = {
        "f013": "5.0.01", "f014": "5.0.02", "f015": "5.0.03",
        "f016": "5.0.04", "f017": "5.0.05", "f100": "5.0.06",
        "f110": "5.0.07", "f200": "5.0.08", "f210": "5.0.09",
    }

    def test_patch_zero_has_the_fixed_portal_and_extended_edition_map(self):
        actual = {target: versioning.distribution_version("5.0.0", target)
                  for target in self.PORTAL}
        self.assertEqual(actual, self.PORTAL)
        self.assertEqual(versioning.distribution_version("5.0.0", "f001"), "5.0.00100")
        self.assertEqual(versioning.distribution_version("5.0.0", "f012"), "5.0.01200")
        self.assertEqual(versioning.distribution_version("5.0.0", "f018"), "5.0.01800")

    def test_patch_ordering_and_examples_preserve_the_edition_digit(self):
        self.assertEqual(versioning.distribution_version("5.0.1", "f210"), "5.0.19")
        self.assertEqual(versioning.distribution_version("5.0.10", "f210"), "5.0.109")
        self.assertEqual(versioning.distribution_version("5.0.1", "f018"), "5.0.01801")
        self.assertEqual(versioning.distribution_version("5.0.10", "f018"), "5.0.01810")
        for target in self.PORTAL:
            with self.subTest(target=target):
                values = [int(versioning.distribution_version("5.0." + str(patch), target).split(".")[-1])
                          for patch in range(100)]
                self.assertEqual(values, sorted(values))

    def test_each_canonical_distribution_round_trips_only_for_its_named_edition(self):
        targets = (*self.PORTAL, "f001", "f012", "f018")
        for target in targets:
            for patch in (0, 1, 10, 99):
                with self.subTest(target=target, patch=patch):
                    source = "5.0." + str(patch)
                    encoded = versioning.distribution_version(source, target)
                    self.assertEqual(versioning.source_version_from_distribution(encoded, target), source)
        with self.assertRaisesRegex(ValueError, "different MIR edition"):
            versioning.source_version_from_distribution("5.0.19", "f200")
        with self.assertRaisesRegex(ValueError, "canonical"):
            versioning.source_version_from_distribution("5.0.009", "f210")

    def test_invalid_source_components_targets_and_collisions_refuse_before_output(self):
        for source in ("5.0.-1", "5.0.100", "65536.0.0", "5.0.00", "5.0.1.0"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                versioning.distribution_version(source, "f210")
        for target in ("f000", "f211", 210):
            with self.subTest(target=target), self.assertRaises(ValueError):
                versioning.distribution_version("5.0.0", target)
        with self.assertRaisesRegex(ValueError, "repeats"):
            versioning.distribution_versions("5.0.0", ("f210", "f210"))
        with self.assertRaisesRegex(ValueError, "invalid source patch"):
            versioning.source_version_from_distribution("5.0.1009", "f210")
        with self.assertRaisesRegex(ValueError, "numeric range"):
            versioning.source_version_from_distribution("5.0.65536", "f210")


if __name__ == "__main__":
    unittest.main()
