"""Host-only controls for the private MIR5 responsive-menu comparison plan.

The tests never invoke -Execute, Factorio, OCR, or package construction.
They validate the fixed plan, missing-seed preflight, and a temporary-file-only
archive swap restoration control.
"""
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/mir5/Invoke-MenuComparison.ps1"


def invoke_as_json(arguments: str) -> dict:
    command = (
        "& { . ./tools/mir5/Invoke-MenuComparison.ps1 "
        f"{arguments} }} | ConvertTo-Json -Depth 32 -Compress"
    )
    completed = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(completed.stdout)


class MenuComparisonTests(unittest.TestCase):
    def test_fixed_plan_contains_warmups_aa_pilot_and_counterbalanced_rows(self):
        record = invoke_as_json("-PlanOnly")
        self.assertEqual(record["status"], "planned-not-executed")
        self.assertTrue(record["fixed_before_execution"])
        self.assertFalse(record["claims"]["native_execution"])
        rows = record["samples"]
        self.assertEqual(len(rows), 14)
        self.assertEqual([row["ordinal"] for row in rows], list(range(1, 15)))
        self.assertEqual(len({row["label"] for row in rows}), 14)

        warmups = [row for row in rows if row["phase"] == "warmup"]
        self.assertEqual([row["arm"] for row in warmups], ["without-mir", "published-4.7", "replay"])
        pilot = [row for row in rows if row["phase"] == "aa-pilot"]
        self.assertEqual([row["arm"] for row in pilot], ["published-4.7", "published-4.7"])
        primary = [row for row in rows if row["phase"] == "counterbalanced-comparison"]
        self.assertEqual(len(primary), 9)
        for arm in ("without-mir", "published-4.7", "replay"):
            self.assertEqual(sorted(row["position"] for row in primary if row["arm"] == arm), [1, 2, 3])

    def test_preflight_reports_the_real_player_data_seed_as_a_prerequisite(self):
        record = invoke_as_json("-Preflight")
        self.assertEqual(record["status"], "blocked-prerequisites")
        self.assertFalse(record["claims"]["native_execution"])
        seed = [row for row in record["missing"] if row["name"] == "PlayerDataPath"]
        self.assertEqual(seed, [{
            "name": "PlayerDataPath",
            "reason": "actual-credential-free-engine-prepared-player-data-required",
            "expected_engine_version": "2.1.23",
        }])

    def test_host_swap_control_restores_bytes_after_action_failure_and_refuses_busy_lock(self):
        record = invoke_as_json("-HostSwapSelfTest")
        self.assertEqual(record["status"], "passed")
        self.assertTrue(record["action_failure_restored"])
        self.assertTrue(record["busy_lock_refused_without_mutation"])
        self.assertFalse(record["claims"]["native_execution"])

    def test_wrapper_delegates_to_the_governed_actor_without_custody_tool_mutation(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("Invoke-MIRDirectLibraryResponsiveMenuSample", source)
        self.assertIn("Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData", source)
        self.assertIn("Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput", source)
        self.assertIn("Assert-MIRLibraryIdle", source)
        self.assertIn("-MaxScanSeconds 1 -MaxEntriesPerRoot 100", source)
        self.assertIn("-Execute only with exclusive native ownership", source)
        self.assertNotIn("Invoke-PrototypeCapture", source)
        self.assertNotIn("Invoke-NativeFixture", source)
        self.assertNotIn("git ", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
