import base64
import gzip
import hashlib
import json
import unittest
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
CHAIN_PATH = ROOT / "spec/evidence/whole-product-heavy-space-age-f210-admission-native-chain-r01.json"
CAPSULE_PATH = ROOT / "spec/evidence/whole-product-heavy-space-age-f210-admission-receipts-r01.json.gz"
CAPSULE_SHA256 = "A2EA6C54DEB646E3FCB0D26A37931DEBC35FA93B71EF05CCC2A9B8C2081D8903"


class WholeProductHeavyF210DataAdmissionEvidenceTests(unittest.TestCase):
    def test_lossless_receipts_preserve_four_data_stage_only_observations(self):
        chain = json.loads(CHAIN_PATH.read_text(encoding="utf-8"))
        self.assertEqual(chain["kind"], "MIRWholeProductHeavySpaceAgeF210DataAdmissionNativeChainV1")
        self.assertEqual(chain["status"], "completed-data-stage-admission-only")
        self.assertEqual(chain["source_commit"], "b7caa8df9141523a556bb57ca8faf7c43d250c3d")
        self.assertEqual(chain["engine"]["version"], "2.1.23")
        self.assertEqual(chain["engine"]["sha256"], "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38")
        self.assertEqual(chain["profile"]["selected_rows"], 37)
        self.assertEqual(chain["profile"]["official_space_age_rows"], 5)
        self.assertEqual(chain["profile"]["bob_angel_rows"], 31)
        self.assertEqual(chain["profile"]["selected_nonbuiltin_archives"], 32)
        self.assertEqual([row["id"] for row in chain["arms"]], [
            "control-without-mir", "terminal-mir3.2.11", "published-mir4.7", "candidate-mir5",
        ])
        self.assertEqual(chain["native_processes"], 4)
        self.assertEqual(chain["custody"], {
            "source": "D:\\Projects\\Factorio\\mir5-whole-product-capture-fixed-r01\\build\\tmp\\whole-product-heavy-space-age-f210-admission-r01",
            "copy": "D:\\Projects\\Factorio\\more-infinite-research\\build\\qualification\\whole-product-heavy-space-age-f210-admission-r01-controller\\native-captures",
            "files_per_copy": 36,
            "bytes_per_copy": 273372885,
        })
        self.assertFalse(chain["performance_acceptance"])
        self.assertFalse(chain["release_qualification"])

        compressed = CAPSULE_PATH.read_bytes()
        self.assertEqual(len(compressed), 188662)
        self.assertEqual(hashlib.sha256(compressed).hexdigest().upper(), CAPSULE_SHA256)
        self.assertEqual(chain["receipt_capsule"], {
            "path": "spec/evidence/whole-product-heavy-space-age-f210-admission-receipts-r01.json.gz",
            "bytes": 188662,
            "sha256": CAPSULE_SHA256,
            "bodies": 26,
        })
        capsule = json.loads(gzip.decompress(compressed).decode("utf-8"))
        self.assertEqual(capsule["schema"], 1)
        self.assertEqual(capsule["kind"], "MIRWholeProductHeavySpaceAgeF210DataAdmissionReceiptsV1")
        self.assertEqual(len(capsule["files"]), 26)

        files = {}
        for row in capsule["files"]:
            path = PurePosixPath(row["path"])
            self.assertEqual(path.as_posix(), row["path"])
            self.assertFalse(path.is_absolute())
            self.assertNotIn("..", path.parts)
            self.assertNotIn(row["path"], files)
            raw = base64.b64decode(row["base64"], validate=True)
            self.assertEqual(len(raw), row["bytes"])
            self.assertEqual(hashlib.sha256(raw).hexdigest().upper(), row["sha256"])
            files[row["path"]] = raw

        expected_controller = {
            "controller/packet.json", "controller/preparation.json", "controller/Invoke-Owned.ps1",
            "controller/Existing-OwnedArchiveFunctions.ps1", "controller/controller-output.log",
            "controller/controller-exitcode.txt", "controller/valid-verifyonly-readback.json",
            "controller/execution-record/before.json", "controller/execution-record/progress.json",
            "controller/execution-record/terminal.json",
        }
        self.assertEqual({path for path in files if path.startswith("controller/")}, expected_controller)
        results = {}
        for arm in ("control-without-mir", "terminal-mir3.2.11", "published-mir4.7", "candidate-mir5"):
            result = json.loads(files[f"native/{arm}/result.json"])
            selection = json.loads(files[f"native/{arm}/selection.json"])
            self.assertEqual(result["status"], "completed-data-stage-observation-only")
            self.assertEqual(result["endpoint_class"], "factorio-data-stage-dump-only")
            self.assertTrue(result["process"]["passed"])
            self.assertEqual(result["process"]["exit_code"], 0)
            self.assertTrue(result["library_controls_restored"])
            self.assertEqual(
                set(result["loaded_selection"]),
                {f"{row['name']}@{row['version']}" for row in selection["mods"] if row["enabled"]},
            )
            self.assertEqual(set(result["claims"]), {"gameplay", "menu", "save", "release_qualification"})
            self.assertFalse(any(result["claims"].values()))
            results[arm] = result

        self.assertNotIn("more-infinite-research@", "\n".join(results["control-without-mir"]["loaded_selection"]))
        for arm, version in (("terminal-mir3.2.11", "3.2.11"),
                             ("published-mir4.7", "4.7.21003"),
                             ("candidate-mir5", "5.0.21000")):
            self.assertIn(f"more-infinite-research@{version}", results[arm]["loaded_selection"])
            self.assertEqual(len(results[arm]["loaded_selection"]), 38)
        self.assertEqual(len(results["control-without-mir"]["loaded_selection"]), 37)
        for observation in chain["observations"]:
            result = results[observation["arm"]]
            self.assertEqual(observation["loaded_selection"], result["loaded_selection"])
            self.assertEqual(observation["dumps"], result["dumps"])
            self.assertEqual(observation["native_processes"], len(result["process_runs"]))
            self.assertEqual(observation["exit_code"], result["process"]["exit_code"])


if __name__ == "__main__":
    unittest.main()
