"""Independent controls for the R06 active-runtime benchmark result reader."""
from __future__ import annotations

import copy
import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools" / "analyze_runtime_benchmark.py"
SPEC = importlib.util.spec_from_file_location("runtime_benchmark_analysis", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest().upper()


def _encode(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _profile(path: str, token: str) -> dict[str, str]:
    return {"path": path, "sha256": token * 64}


def _plan() -> dict[str, object]:
    helpers = [
        {"path": f"tools/helper-{index}.ps1", "sha256": f"{index:X}" * 64}
        for index in range(1, 13)
    ]
    repair_profiles = [
        _profile("tests/profiles/repair-stress-active-published-f210-2123.json", "A"),
        _profile("tests/profiles/repair-stress-active-mir5-f210-2123.json", "B"),
    ]
    agriculture_profiles = [
        _profile(f"tests/profiles/agriculture-active-matched-{arm}-{tier}-f210-2123.json", token)
        for tier, token_pair in ((1, ("C", "D")), (32, ("E", "F")), (128, ("1", "2")))
        for arm, token in zip(("published", "candidate-defaults"), token_pair, strict=True)
    ]
    return {
        "schema": 1,
        "kind": MODULE.PLAN_KIND,
        "status": "predeclared-active-save-capture-required-not-a-result",
        "plan_source": {"commit": MODULE.PLAN_SOURCE, "tree": MODULE.PLAN_TREE},
        "candidate": {
            "source_commit": MODULE.SOURCE,
            "source_tree": MODULE.SOURCE_TREE,
            "asset_root": "D:/Projects/Factorio/mir5-current-assets-b2cf4c2d-r01",
            "asset_inventory_file_sha256": MODULE.INVENTORY_SHA256,
            "asset_inventory_content_sha256": MODULE.INVENTORY_CONTENT_SHA256,
            "f210_archive": {"name": "more-infinite-research_5.0.21000.zip", "bytes": 553767, "sha256": MODULE.CANDIDATE_SHA256},
        },
        "published": {"f210_archive": {"name": "more-infinite-research_4.7.21002.zip", "sha256": MODULE.PUBLISHED_SHA256}},
        "engine": {"version": "2.1.23", "sha256": MODULE.ENGINE_SHA256},
        "public_harness": {"source_reference": MODULE.PLAN_SOURCE, "git_blob_sha256": helpers},
        "benchmark_command": {
            "arguments": ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"],
        },
        "process_memory_observation": {
            "context": "benchmark",
            "expected_slot": {"phase": "benchmark", "role": "factorio"},
            "target_interval_milliseconds": 250,
            "maximum_duration_seconds": 900,
            "maximum_observations": 12000,
            "maximum_serialized_bytes": 8 * 1024 * 1024,
        },
        "comparison_rules": {
            "candidate_time_per_tick_limit": {"relative_fraction": 0.1, "absolute_milliseconds_per_tick": 0.25},
            "candidate_memory_limits": {"relative_fraction": 0.1, "absolute_bytes": 64 * 1024 * 1024, "metrics": list(MODULE.METRICS[1:])},
            "agriculture_within_arm_increment_128_minus_1": {
                "metrics": list(MODULE.METRICS),
                "rule": "Report candidate and published 128-minus-1 raw differences separately. A percentage comparison is permitted only when the matching published incremental denominator is finite and strictly positive; otherwise report raw differences only, with no percentage or inferred non-regression conclusion from noise.",
            },
        },
        "resources": {
            "expected_peak_memory_mib_per_factorio": 4096,
            "maximum_new_output_mib_per_launch": 120,
            "exclusive_native_lock": True,
            "direct_existing_archive_library_only": True,
            "no_dependency_copy_hardlink_or_extraction": True,
        },
        "schedule": {
            "repair_active": {"warmups_per_arm": 2, "scored_pairs": 8, "arms": ["published", "candidate"]},
            "agriculture_active": {"warmups_per_arm_per_tier": 2, "scored_pairs_per_tier": 6, "tiers": [1, 32, 128], "arms": ["published", "candidate-defaults"]},
            "total_launches": 68,
        },
        "active_fixture_contract": {
            "repair": {"profiles": repair_profiles, "required_markers": ["prepared", "start", "complete"]},
            "agriculture": {"profiles": agriculture_profiles, "required_markers": ["prepared", "start", "complete"]},
        },
        "active_seed_capture": {
            "repair": {"count": 2},
            "agriculture": {"count": 6},
            "closed_save_name": "mir5-native-active.zip",
            "preparation_outside_timed_benchmark": True,
        },
        "unscored_marker_pilot": {"count": 8, "ticks": 25000, "not_in_schedule_total": True, "not_a_timing_or_acceptance_result": True},
        "performance_acceptance": False,
        "release_qualification": False,
    }


def _marker(kind: str, stage: str, status: str, witnesses: dict[str, object]) -> dict[str, object]:
    return {"kind": kind, "stage": stage, "status": status, "witnesses": witnesses}


def _prepared_witness(row: dict[str, object]) -> dict[str, object]:
    if row["kind"] == "repair-stress":
        return {"total_eligible_walls": 1000, "first_capacity_walls": 256, "eligible_overflow_walls": 744, "initial_changed": 0, "pending_physical_work": True}
    return {
        "real_lab_agriculture_completions": 2,
        "native_planting_events": {"observed": 0, "expected": 2 * int(row["tier"])},
        "pending_physical_work": True,
    }


def _pilot_witness(row: dict[str, object], complete: bool) -> dict[str, object]:
    if row["kind"] == "repair-stress":
        return {
            "total_eligible_walls": 1000,
            "first_capacity_walls": 256,
            "eligible_overflow_walls": 744,
            "initial_changed": 256 if complete else 0,
            "reactivation_changed": 8 if complete else 0,
            "pending_physical_work": not complete,
        }
    arm = "published-4.7.21002" if row["arm"] == "published" else "candidate-defaults-mir5"
    tier = int(row["tier"])
    return {
        "tier": tier,
        "arm": arm,
        "real_lab_agriculture_completions": 2,
        "native_towers": {"player": tier, "foreign_zero_research": tier},
        "native_planting_events": {"observed": 2 * tier if complete else 0, "expected": 2 * tier},
        "pending_physical_work": not complete,
    }


def _profile_for(plan: dict[str, object], scenario: str, tier: int, arm: str) -> dict[str, str]:
    return MODULE._profiles(plan)[(scenario, tier, arm)]


def _independent_schedule() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []

    def append(identifier: str, phase: str, scenario: str, tier: int, arm: str, block: int | None) -> None:
        rows.append({"ordinal": len(rows) + 1, "id": identifier, "phase": phase, "scenario": scenario, "tier": tier, "arm": arm, "block": block})

    for arm in ("published", "candidate"):
        for number in range(1, 3):
            append(f"repair-warmup-{arm}-{number}", "warmup", "repair-active", 0, arm, None)
    for block in range(1, 9):
        for position, arm in enumerate(("published", "candidate") if block % 2 else ("candidate", "published"), start=1):
            append(f"repair-b{block}-{position}-{arm}", "scored", "repair-active", 0, arm, block)
    for tier in (1, 32, 128):
        for arm in ("published", "candidate-defaults"):
            for number in range(1, 3):
                append(f"agriculture-{tier}-warmup-{arm}-{number}", "warmup", "agriculture-active", tier, arm, None)
        for block in range(1, 7):
            for position, arm in enumerate(("published", "candidate-defaults") if block % 2 else ("candidate-defaults", "published"), start=1):
                append(f"agriculture-{tier}-b{block}-{position}-{arm}", "scored", "agriculture-active", tier, arm, block)
    if len(rows) != 68:
        raise AssertionError("independent schedule size differs")
    return rows


def _capture_and_pilot(plan: dict[str, object], plan_sha: str) -> tuple[dict[str, object], dict[str, object]]:
    captures: list[dict[str, object]] = []
    pilots: list[dict[str, object]] = []
    for index, active in enumerate(MODULE._active_rows(), start=1):
        scenario = "repair-active" if active["kind"] == "repair-stress" else "agriculture-active"
        profile = _profile_for(plan, scenario, int(active["tier"]), str(active["arm"]))
        staged_profile = {**profile, "path": "D:/owned/pinned-source/" + profile["path"]}
        seed_hash = f"{index:X}" * 64
        prepared = _marker(str(active["kind"]), "prepared", "pending", _prepared_witness(active))
        capture = {
            **active,
            "profile": staged_profile,
            "active_seed": {"path": f"D:/custody/{active['id']}/mir5-native-active.zip", "sha256": seed_hash, "bytes": 99 + index},
            "prepared_marker": prepared,
            "native_result_path": f"D:/custody/{active['id']}/result.json",
            "native_result_sha256": ("A" if index % 2 else "B") * 64,
        }
        captures.append(capture)
        pilots.append({
            "id": active["id"],
            "kind": active["kind"],
            "arm": active["arm"],
            "tier": active["tier"],
            "prepared_marker": prepared,
            "start_marker": _marker(str(active["kind"]), "start", "pending", _pilot_witness(active, False)),
            "complete_marker": _marker(str(active["kind"]), "complete", "passed", _pilot_witness(active, True)),
            "stdout": f"{active['id']}/factorio-current.log",
            "stdout_sha256": ("C" if index % 2 else "D") * 64,
        })
    capture_record = {
        "schema": 1,
        "kind": MODULE.CAPTURE_KIND,
        "status": "prepared-active-saves-not-a-benchmark-result",
        "plan": {"sha256": plan_sha, "source_revision": MODULE.PLAN_SOURCE},
        "public_harness": {"source_reference": MODULE.PLAN_SOURCE},
        "captures": captures,
        "preparation_outside_timed_benchmark": True,
        "performance_acceptance": False,
        "release_qualification": False,
    }
    capture_reference = {"path": "D:/custody/active-seeds.json", "sha256": MODULE.ACTIVE_SEED_CAPTURE_SHA256, "kind": MODULE.CAPTURE_KIND, "status": capture_record["status"], "record": capture_record}
    pilot_record = {
        "schema": 1,
        "kind": MODULE.PILOT_KIND,
        "status": "complete-unscored-not-a-performance-result",
        "plan_sha256": plan_sha,
        "active_seed_receipt": {"path": capture_reference["path"], "sha256": capture_reference["sha256"]},
        "observations": pilots,
        "schedule_launches": 0,
        "performance_acceptance": False,
        "release_qualification": False,
    }
    return capture_reference, {"path": "D:/custody/marker-pilot.json", "sha256": MODULE.MARKER_PILOT_SHA256, "kind": MODULE.PILOT_KIND, "status": pilot_record["status"], "record": pilot_record}


def _value(schedule: dict[str, object]) -> float:
    if schedule["phase"] == "warmup":
        return 99.0
    block = int(schedule["block"])
    if schedule["scenario"] == "repair-active":
        return (10.0 if schedule["arm"] == "published" else 11.0) + block
    base = {1: 4.0, 32: 6.0, 128: 9.0}[int(schedule["tier"])]
    return base + (0.5 if schedule["arm"] == "candidate-defaults" else 0.0) + block


def _observation(plan: dict[str, object], schedule: dict[str, object], captures: dict[str, object]) -> dict[str, object]:
    scenario = str(schedule["scenario"])
    tier = int(schedule["tier"])
    arm = str(schedule["arm"])
    profile = _profile_for(plan, scenario, tier, arm)
    staged_profile = {**profile, "path": "D:/owned/pinned-source/" + profile["path"]}
    capture_id = f"repair-{arm}" if scenario == "repair-active" else f"agriculture-{arm}-{tier}"
    capture = next(item for item in captures["record"]["captures"] if item["id"] == capture_id)
    value = _value(schedule)
    working = 1000 + int(value * 10)
    private = 5000 if scenario == "agriculture-active" else 500 + int(value * 10)
    selected = MODULE.PUBLISHED_SHA256 if arm == "published" else MODULE.CANDIDATE_SHA256
    selected_leaf = "more-infinite-research_4.7.21002.zip" if arm == "published" else "more-infinite-research_5.0.21000.zip"
    active = {"kind": "repair-stress" if scenario == "repair-active" else "agriculture-scale", "arm": arm, "tier": tier}
    return {
        "kind": MODULE.SAMPLE_KIND,
        "status": "observed-not-performance-accepted",
        "id": schedule["id"],
        "scored": schedule["phase"] == "scored",
        "scenario": scenario,
        "tier": tier,
        "arm": arm,
        "engine": {"version": "2.1.23", "sha256": MODULE.ENGINE_SHA256},
        "profile": staged_profile,
        "archives": {selected_leaf: selected},
        "seed": {
            "source_path": capture["active_seed"]["path"],
            "source_sha256": capture["active_seed"]["sha256"],
            "owned_leaf": "fresh-owned-active-seed.zip",
            "owned_path": f"D:/owned/{schedule['id']}/fresh-owned-active-seed.zip",
            "owned_sha256": capture["active_seed"]["sha256"],
            "bytes": capture["active_seed"]["bytes"],
        },
        "seed_integrity_after_sample": {
            "checkpoint": "after-sample",
            "sample_id": schedule["id"],
            "source": {"expected_sha256": capture["active_seed"]["sha256"], "actual_sha256": capture["active_seed"]["sha256"], "unchanged": True},
            "owned": {"expected_sha256": capture["active_seed"]["sha256"], "actual_sha256": capture["active_seed"]["sha256"], "unchanged": True},
        },
        "command": ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"],
        "timing": {"updates": 25000, "total_milliseconds": value * 25000, "average_milliseconds_per_tick": value, "minimum_milliseconds_per_tick": value - 0.1, "maximum_milliseconds_per_tick": value + 0.1},
        "native_process": {
            "stdout": f"{schedule['id']}/factorio-current.log",
            "stdout_sha256": "A" * 64,
            "resource_ledger": f"{schedule['id']}/resource-ledger.json",
            "duration_seconds": 2.0,
            "root_os_reported_peak_working_set_bytes": working + 100,
            "maximum_sampled_working_set_bytes": working,
            "maximum_sampled_private_bytes": private,
            "sampled_observation_count": 1,
        },
        "process_memory": {"status": "complete-observation", "context": "benchmark", "observations": [{"phase": "benchmark", "role": "factorio", "pid": 100, "start_utc": "2026-01-01T00:00:00Z", "working_set_bytes": working, "private_bytes": private}]},
        "physical_markers": {
            "start": _marker(str(active["kind"]), "start", "pending", _pilot_witness(active, False)),
            "complete": _marker(str(active["kind"]), "complete", "passed", _pilot_witness(active, True)),
            "fixture_log": f"{schedule['id']}/fixture.log",
            "fixture_log_sha256": "D" * 64,
            "stdout": f"{schedule['id']}/factorio-current.log",
            "stdout_sha256": "A" * 64,
        },
        "library_control_restoration": {"status": "restored-direct-library-controls", "profile_sha256": profile["sha256"], "dependency_payload_bytes_copied": 0, "archive_links_created": 0, "archive_extractions": 0, "selected": []},
        "performance_acceptance": False,
        "release_qualification": False,
    }


def _result(plan: dict[str, object]) -> tuple[dict[str, object], str]:
    plan_sha = _hash(_encode(plan))
    schedule = _independent_schedule()
    captures, pilot = _capture_and_pilot(plan, plan_sha)
    members = [
        {"path": row["path"], "raw_git_sha256": row["sha256"], "executed_sha256": row["sha256"], "bytes": 1}
        for row in plan["public_harness"]["git_blob_sha256"]
    ]
    result = {
        "schema": 1,
        "kind": MODULE.RESULT_KIND,
        "status": "observed-not-performance-accepted",
        "plan": {"path": MODULE.PLAN_PATH, "source_revision": MODULE.PLAN_REVISION, "sha256": plan_sha},
        "private_controller": {"revision": "a" * 40, "path": "Invoke-RuntimeBenchmark.ps1", "raw_git_sha256": "B" * 64, "executed_sha256": "B" * 64, "executed_matches_raw_git": True},
        "raw_helper_source": {"revision": MODULE.PLAN_SOURCE, "members": members},
        "prepared_inputs_path": "runtime-benchmark-active-prepared.json",
        "prepared_inputs_sha256": "C" * 64,
        "active_seed_capture": captures,
        "unscored_marker_pilot": pilot,
        "schedule": schedule,
        "observations": [_observation(plan, item, captures) for item in schedule],
        "performance_qualification": False,
        "release_qualification": False,
    }
    return result, plan_sha


def _prepared_inputs(result: dict[str, object]) -> bytes:
    return _encode({
        "schema": 1,
        "kind": "MIR5ActiveRuntimeBenchmarkPreparedInputsV1",
        "status": "validated-accepted-active-inputs-no-new-native",
        "plan": result["plan"],
        "private_controller": result["private_controller"],
        "raw_helper_source": result["raw_helper_source"],
        "active_seed_capture": result["active_seed_capture"],
        "unscored_marker_pilot": result["unscored_marker_pilot"],
        "schedule": result["schedule"],
        "native_launches": 0,
        "performance_qualification": False,
        "release_qualification": False,
    })


class RuntimeBenchmarkAnalysisTests(unittest.TestCase):
    def test_consumes_exact_accepted_r06_capture_and_pilot_payloads(self) -> None:
        capsule_path = "spec/evidence/runtime-active-r06-physical-native-receipts.json.gz"
        plan_path = "spec/evidence/runtime-benchmark-active-plan-r06.json"

        def read_tracked(path: str) -> bytes:
            # CI checks out this accepted evidence as source, but does not promise
            # historical object reachability for its original evidence commit.
            subprocess.check_call(["git", "ls-files", "--error-unmatch", "--", path], cwd=ROOT)
            return (ROOT / path).read_bytes()

        capsule_bytes = read_tracked(capsule_path)
        self.assertEqual(_hash(capsule_bytes), "23466064A3C2E376A93FAFD9D5772038186BF4FB5D993E56953F5B145AD5FE88")
        capsule = json.loads(gzip.decompress(capsule_bytes))
        raw_records = {
            entry["path"]: base64.b64decode(entry["base64"])
            for entry in capsule["files"]
            if entry["path"] in {"original/active-seed-captures.json", "original/active-marker-pilots.json"}
        }
        capture_bytes = raw_records["original/active-seed-captures.json"]
        pilot_bytes = raw_records["original/active-marker-pilots.json"]
        self.assertEqual(_hash(capture_bytes), MODULE.ACTIVE_SEED_CAPTURE_SHA256)
        self.assertEqual(_hash(pilot_bytes), MODULE.MARKER_PILOT_SHA256)
        plan_bytes = read_tracked(plan_path)
        self.assertEqual(_hash(plan_bytes), "816BA8FE3589967CC456F189F5F3F584289FB553DAFADBB64ACAEF32DD306C4F")
        plan = json.loads(plan_bytes)
        plan_sha = _hash(plan_bytes)
        capture = json.loads(capture_bytes)
        pilot = json.loads(pilot_bytes)
        capture_reference = {
            "path": "original/active-seed-captures.json",
            "sha256": MODULE.ACTIVE_SEED_CAPTURE_SHA256,
            "kind": capture["kind"],
            "status": capture["status"],
            "record": capture,
        }
        captures = MODULE._validate_capture_reference(capture_reference, plan_sha, MODULE._profiles(plan))
        pilot_reference = {
            "path": "original/active-marker-pilots.json",
            "sha256": MODULE.MARKER_PILOT_SHA256,
            "kind": pilot["kind"],
            "status": pilot["status"],
            "record": pilot,
        }
        MODULE._validate_pilot_reference(pilot_reference, plan_sha, capture_reference, captures)
        MODULE._validate_process_memory(pilot["observations"][0]["native_result"]["process_memory"], pilot["observations"][0]["native_result"]["native_process"])

    def test_complete_r06_result_reports_known_medians_and_increment_rules(self) -> None:
        plan = _plan()
        result, plan_sha = _result(plan)
        output = MODULE.analyze(plan, plan_sha, result, _hash(_encode(result)))
        repair_time = output["comparisons"]["repair_active"]["metrics"]["engine_reported_average_milliseconds_per_tick"]
        self.assertEqual(repair_time["published"]["median"], 14.5)
        self.assertEqual(repair_time["candidate"]["median"], 15.5)
        self.assertEqual(repair_time["limit"], 15.95)
        self.assertEqual(repair_time["status"], "within-predeclared-limit")
        self.assertEqual(output["schedule"][0]["id"], "repair-warmup-published-1")
        self.assertEqual(output["schedule"][-1]["id"], "agriculture-128-b6-2-published")
        self.assertEqual(output["paired_block_differences"]["repair_active"][0]["candidate_minus_published"]["engine_reported_average_milliseconds_per_tick"], 1.0)
        time_increment = output["agriculture_128_minus_1"]["candidate_defaults"]["engine_reported_average_milliseconds_per_tick"]
        self.assertEqual(time_increment["raw_128_minus_1"], 5.0)
        self.assertEqual(time_increment["percent_of_published_increment"], 100.0)
        private_increment = output["agriculture_128_minus_1"]["candidate_defaults"]["maximum_sampled_private_bytes"]
        self.assertIsNone(private_increment["percent_of_published_increment"])
        self.assertEqual(private_increment["percentage_status"], "unresolved-nonpositive-or-nonfinite-published-denominator")
        self.assertFalse(output["claims"]["release_qualification"])
        self.assertFalse(output["claims"]["equivalence_claim"])

    def test_refuses_schedule_seed_pilot_restoration_and_identity_opponents(self) -> None:
        plan = _plan()
        result, plan_sha = _result(plan)
        opponents: dict[str, callable] = {
            "wrong-odd-arm-order": lambda item: item["schedule"].__setitem__(4, {**item["schedule"][4], "arm": "candidate"}),
            "wrong-canonical-id": lambda item: item["schedule"].__setitem__(0, {**item["schedule"][0], "id": "not-the-r06-first-warmup"}),
            "duplicate-schedule-id": lambda item: item["schedule"].__setitem__(1, {**item["schedule"][1], "id": item["schedule"][0]["id"]}),
            "wrong-seed-capture": lambda item: item["observations"][0]["seed"].__setitem__("source_sha256", "0" * 64),
            "wrong-accepted-capture-receipt": lambda item: item["active_seed_capture"].__setitem__("sha256", "0" * 64),
            "wrong-accepted-pilot-receipt": lambda item: item["unscored_marker_pilot"].__setitem__("sha256", "0" * 64),
            "wrong-prepared-inputs-leaf": lambda item: item.__setitem__("prepared_inputs_path", "other.json"),
            "relative-capture-profile": lambda item: item["active_seed_capture"]["record"]["captures"][0]["profile"].__setitem__("path", "tests/profiles/repair-stress-active-published-f210-2123.json"),
            "flat-prepared-planting": lambda item: item["active_seed_capture"]["record"]["captures"][2]["prepared_marker"]["witnesses"].__setitem__("native_planting_events", 0),
            "pilot-complete-witness": lambda item: item["unscored_marker_pilot"]["record"]["observations"][0]["complete_marker"]["witnesses"].__setitem__("initial_changed", 1),
            "sample-complete-witness": lambda item: item["observations"][0]["physical_markers"]["complete"]["witnesses"].__setitem__("initial_changed", 1),
            "nonrestored-library": lambda item: item["observations"][0]["library_control_restoration"].__setitem__("status", "not-restored"),
            "wrong-engine": lambda item: item["observations"][0]["engine"].__setitem__("sha256", "0" * 64),
            "nonfinite-timing": lambda item: item["observations"][0]["timing"].__setitem__("average_milliseconds_per_tick", float("nan")),
            "missing-observation": lambda item: item["observations"].pop(),
        }
        for label, mutate in opponents.items():
            with self.subTest(label=label):
                bad = copy.deepcopy(result)
                mutate(bad)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    MODULE.analyze(plan, plan_sha, bad, _hash(_encode(bad)))

    def test_cli_requires_external_raw_plan_and_result_hashes(self) -> None:
        plan = _plan()
        result, _ = _result(plan)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan_path = root / "plan.json"
            result_path = root / "result.json"
            output_path = root / "analysis.json"
            plan_bytes = _encode(plan)
            prepared_bytes = _prepared_inputs(result)
            result["prepared_inputs_sha256"] = _hash(prepared_bytes)
            result_bytes = _encode(result)
            plan_path.write_bytes(plan_bytes)
            result_path.write_bytes(result_bytes)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(prepared_bytes)
            success = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", _hash(result_bytes), "--output", str(output_path)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(success.returncode, 0, success.stderr)
            self.assertTrue(output_path.is_file())
            for argument in ("--expected-plan-sha256", "--expected-result-sha256"):
                failed = subprocess.run(
                    [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", "0" * 64 if argument == "--expected-plan-sha256" else _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", "0" * 64 if argument == "--expected-result-sha256" else _hash(result_bytes), "--output", str(root / (argument[2:] + ".json"))],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(failed.returncode, 1)
                self.assertIn("mir5-runtime-benchmark-analysis-refused", failed.stderr)
            stale_sidecar = json.loads(prepared_bytes)
            stale_sidecar["schedule"][0]["id"] = "stale-schedule-row"
            stale_bytes = _encode(stale_sidecar)
            result["prepared_inputs_sha256"] = _hash(stale_bytes)
            stale_result_bytes = _encode(result)
            result_path.write_bytes(stale_result_bytes)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(stale_bytes)
            stale = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", _hash(stale_result_bytes), "--output", str(root / "stale-sidecar.json")],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(stale.returncode, 1)
            self.assertIn("prepared inputs sidecar schedule differs", stale.stderr)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(b"{}\n")
            invalid_sidecar = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", _hash(stale_result_bytes), "--output", str(root / "invalid-sidecar.json")],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(invalid_sidecar.returncode, 1)
            self.assertIn("prepared inputs sidecar SHA-256 differs", invalid_sidecar.stderr)


if __name__ == "__main__":
    unittest.main()
