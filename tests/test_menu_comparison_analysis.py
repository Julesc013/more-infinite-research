#!/usr/bin/env python3
"""Independent synthetic controls for the frozen R23 menu analysis reader."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "analyze_menu_comparison.py"
SPEC_PATH = ROOT / "spec" / "evidence" / "bob-angel-menu-r23-analysis-plan-r01.json"
SPEC = importlib.util.spec_from_file_location("analyze_menu_comparison", MODULE_PATH)
assert SPEC and SPEC.loader
ANALYZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ANALYZER)


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest().upper()


def _encoded(document: object) -> bytes:
    return json.dumps(document, indent=2, sort_keys=True).encode("utf-8") + b"\n"


def _analysis_plan() -> dict[str, object]:
    return json.loads(SPEC_PATH.read_text(encoding="utf-8"))


def _raw_plan(plan: dict[str, object]) -> dict[str, object]:
    identity = plan["identity"]
    candidate = identity["candidate"]
    return {
        "schema": 1,
        "kind": "MIR5PredeclaredResponsiveMenuExperimentV1",
        "engine": copy.deepcopy(identity["engine"]),
        "profile": identity["profile"]["path"],
        "profile_checkout_sha256": identity["profile"]["sha256"],
        "published": copy.deepcopy(identity["published"]),
        "candidate": {
            "source_reference": identity["source_reference"],
            "source_tree": identity["source_tree"],
            "sha256": candidate["sha256"],
            "bytes": candidate["bytes"],
            "asset_inventory_sha256": candidate["asset_inventory_sha256"],
        },
        "ordinary_config_sha256": identity["ordinary_config_sha256"],
        "player_data_sha256": identity["player_data_sha256"],
        "tolerances": {
            "aa_absolute_seconds": plan["tolerance_policy"]["aa_absolute_seconds"],
            "aa_relative_percent": plan["tolerance_policy"]["aa_relative_percent"],
            "control_regression_seconds": plan["tolerance_policy"]["control_regression_seconds"],
            "minimum_mir_added_time_reduction_percent": plan["tolerance_policy"]["minimum_mir_added_time_reduction_percent"],
        },
    }


def _execution_tolerance(plan: dict[str, object]) -> dict[str, float]:
    tolerance = plan["tolerance_policy"]
    return {
        "aa_absolute_tolerance_seconds": tolerance["aa_absolute_seconds"],
        "aa_relative_tolerance_percent": tolerance["aa_relative_percent"],
        "control_regression_tolerance_seconds": tolerance["control_regression_seconds"],
        "minimum_mir_added_time_reduction_percent": tolerance["minimum_mir_added_time_reduction_percent"],
    }


def _result(
    plan: dict[str, object],
    *,
    controls: list[float] | None = None,
    published_offsets: list[float] | None = None,
    candidate_offsets: list[float] | None = None,
    replay_offsets: list[float] | None = None,
    aa: tuple[float, float] = (12.0, 12.1),
) -> dict[str, object]:
    expected = ANALYZER._expected_schedule(plan["schedule"])
    controls = controls or [10.0] * 8
    published_offsets = published_offsets or [2.0] * 8
    candidate_offsets = candidate_offsets or [1.0] * 8
    replay_offsets = replay_offsets or [1.5] * 8
    assert len(controls) == len(published_offsets) == len(candidate_offsets) == len(replay_offsets) == 8
    identity = plan["identity"]
    inputs = {
        "factorio": {"base_version": identity["engine"]["version"], "sha256": identity["engine"]["sha256"]},
        "profile": {"path": identity["profile"]["path"], "sha256": identity["profile"]["sha256"]},
        "published": {"version": identity["published"]["version"], "sha256": identity["published"]["sha256"]},
        "replay": {"version": identity["published"]["version"], "sha256": "A" * 64},
        "candidate": {"sha256": identity["candidate"]["sha256"], "bytes": identity["candidate"]["bytes"]},
        "ordinary_player_config": {"sha256": identity["ordinary_config_sha256"]},
        "player_data": {"sha256": identity["player_data_sha256"]},
    }
    samples: list[dict[str, object]] = []
    for row in expected:
        if row["phase"] == "warmup":
            elapsed = 9.0
        elif row["phase"] == "aa-pilot":
            elapsed = aa[row["position"] - 1]
        else:
            index = row["block"] - 1
            control = controls[index]
            elapsed = {
                "control-without-mir": control,
                "published-4.7": control + published_offsets[index],
                "candidate-mir5": control + candidate_offsets[index],
                "replay": control + replay_offsets[index],
            }[row["arm"]]
        samples.append(
            {
                "plan": copy.deepcopy(row),
                "observation": {
                    "status": "validated-recorded-menu-interaction-response",
                    "endpoint_class": "ordinary-responsive-menu",
                    "elapsed_seconds": elapsed,
                    "clock_frequency": 1_000_000,
                    "process_id": row["ordinal"],
                },
            }
        )
    return {
        "schema": 1,
        "kind": "MIR5ResponsiveMenuComparisonObservationV1",
        "status": "completed-observation-only",
        "endpoint_class": "ordinary-responsive-menu",
        "plan": {"fixed_before_execution": True, "tolerance_policy": _execution_tolerance(plan), "samples": copy.deepcopy(expected)},
        "inputs": inputs,
        "samples": samples,
        "library_controls_restored": True,
        "claims": {
            "native_execution": True,
            "performance_measurement": False,
            "performance_comparison": False,
            "release_qualification": False,
        },
    }


def _prepared() -> tuple[dict[str, object], dict[str, object], str]:
    plan = _analysis_plan()
    raw = _raw_plan(plan)
    raw_hash = _sha256(_encoded(raw))
    plan["raw_plan"]["sha256"] = raw_hash
    return plan, raw, raw_hash


class MenuComparisonAnalysisTests(unittest.TestCase):
    def test_hand_computed_paired_result_supports_fifty_percent_objective(self) -> None:
        plan, raw, raw_hash = _prepared()
        result = _result(plan)
        output = ANALYZER.analyze(plan, raw, raw_hash, result, "B" * 64)
        self.assertEqual(output["summaries"]["published_added_time_d4_seconds"]["arithmetic_mean_seconds"], 2.0)
        self.assertEqual(output["summaries"]["candidate_added_time_d5_seconds"]["arithmetic_mean_seconds"], 1.0)
        self.assertEqual(output["summaries"]["direct_candidate_minus_published_seconds"]["arithmetic_mean_seconds"], -1.0)
        self.assertEqual(output["objective"]["reduction_percent"], 50.0)
        self.assertEqual(output["objective"]["status"], "credible-at-least-50-percent")
        self.assertEqual(output["menu_verdict"]["status"], "analysis-complete-objective-supported")

    def test_zero_or_uncertain_published_increment_refuses_percentage_claim(self) -> None:
        plan, raw, raw_hash = _prepared()
        zero = ANALYZER.analyze(plan, raw, raw_hash, _result(plan, published_offsets=[0.0] * 8), "C" * 64)
        self.assertIsNone(zero["objective"]["reduction_percent"])
        self.assertEqual(zero["objective"]["status"], "unresolved-nonpositive-or-uncertain-published-increment")
        plan, raw, raw_hash = _prepared()
        uncertain = ANALYZER.analyze(
            plan,
            raw,
            raw_hash,
            _result(plan, published_offsets=[2.0, -1.0, 2.0, -1.0, 2.0, -1.0, 2.0, -1.0]),
            "D" * 64,
        )
        self.assertIsNone(uncertain["objective"]["reduction_percent"])
        self.assertIn("published-added-time-denominator-unresolved", uncertain["menu_verdict"]["adverse_or_unresolved"])

    def test_aa_and_control_drift_remain_explicit_adverse_observations(self) -> None:
        plan, raw, raw_hash = _prepared()
        aa = ANALYZER.analyze(plan, raw, raw_hash, _result(plan, aa=(10.0, 12.0)), "E" * 64)
        self.assertEqual(aa["same_version_aa"]["status"], "adverse-outside-predeclared-tolerance")
        self.assertIn("same-version-aa-outside-predeclared-tolerance", aa["menu_verdict"]["adverse_or_unresolved"])
        plan, raw, raw_hash = _prepared()
        drift = ANALYZER.analyze(plan, raw, raw_hash, _result(plan, controls=[10.0] * 4 + [11.0] * 4), "F" * 64)
        self.assertEqual(drift["control_drift"]["late_minus_early_seconds"], 1.0)
        self.assertEqual(drift["control_drift"]["status"], "adverse-outside-predeclared-tolerance")
        self.assertIn("late-control-drift-outside-predeclared-tolerance", drift["menu_verdict"]["adverse_or_unresolved"])

    def test_row_badness_and_identity_mismatch_are_refused(self) -> None:
        plan, raw, raw_hash = _prepared()
        bad_elapsed = _result(plan)
        bad_elapsed["samples"][6]["observation"]["elapsed_seconds"] = 0.0
        with self.assertRaisesRegex(ANALYZER.MenuAnalysisError, "must be positive"):
            ANALYZER.analyze(plan, raw, raw_hash, bad_elapsed, "1" * 64)
        bad_label = _result(plan)
        bad_label["samples"][7]["plan"]["label"] = bad_label["samples"][6]["plan"]["label"]
        with self.assertRaisesRegex(ANALYZER.MenuAnalysisError, "schedule row"):
            ANALYZER.analyze(plan, raw, raw_hash, bad_label, "2" * 64)
        bad_identity = _result(plan)
        bad_identity["inputs"]["candidate"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ANALYZER.MenuAnalysisError, "candidate SHA-256"):
            ANALYZER.analyze(plan, raw, raw_hash, bad_identity, "3" * 64)

    def test_cli_binds_expected_raw_result_hash_before_writing_output(self) -> None:
        plan, raw, _ = _prepared()
        result = _result(plan)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            raw_bytes = _encoded(raw)
            raw_hash = _sha256(raw_bytes)
            plan["raw_plan"]["sha256"] = raw_hash
            analysis_path = root / "analysis.json"
            raw_path = root / "raw-plan.json"
            result_path = root / "result.json"
            output_path = root / "output.json"
            analysis_path.write_bytes(_encoded(plan))
            raw_path.write_bytes(raw_bytes)
            result_bytes = _encoded(result)
            result_path.write_bytes(result_bytes)
            self.assertEqual(
                ANALYZER.main(
                    [
                        "--analysis-plan", str(analysis_path),
                        "--raw-plan", str(raw_path),
                        "--result", str(result_path),
                        "--expected-result-sha256", "0" * 64,
                        "--output", str(output_path),
                    ]
                ),
                1,
            )
            self.assertFalse(output_path.exists())
            self.assertEqual(
                ANALYZER.main(
                    [
                        "--analysis-plan", str(analysis_path),
                        "--raw-plan", str(raw_path),
                        "--result", str(result_path),
                        "--expected-result-sha256", _sha256(result_bytes),
                        "--output", str(output_path),
                    ]
                ),
                0,
            )
            self.assertTrue(output_path.exists())


if __name__ == "__main__":
    unittest.main()
