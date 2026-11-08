"""Independent controls for the explicitly frozen active-runtime benchmark cohorts."""
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
import zipfile
from unittest import mock


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


def _accepted_pilot_payload() -> bytes:
    capsule = json.loads(gzip.decompress((ROOT / MODULE.ACTIVE_PREREQUISITES_CAPSULE).read_bytes()))
    return next(
        base64.b64decode(entry["base64"])
        for entry in capsule["files"]
        if entry["path"] == "original/active-marker-pilots.json"
    )


def _pilot_start_utc_values(record: dict[str, object]) -> list[str]:
    return [
        row["start_utc"]
        for observation in record["observations"]
        for row in observation["native_result"]["process_memory"]["observations"]
    ]


def _plan() -> dict[str, object]:
    return json.loads((ROOT / MODULE.PLAN_PATH).read_bytes())


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
    if plan_sha != MODULE.PLAN_SHA256:
        raise AssertionError("synthetic result must retain the frozen R06 plan")
    capture_record, pilot_record = MODULE._frozen_active_prerequisites()
    capture_reference = {
        "path": "original/active-seed-captures.json",
        "sha256": MODULE.ACTIVE_SEED_CAPTURE_SHA256,
        "kind": capture_record["kind"],
        "status": capture_record["status"],
        "record": copy.deepcopy(capture_record),
    }
    return capture_reference, {
        "path": "original/active-marker-pilots.json",
        "sha256": MODULE.MARKER_PILOT_SHA256,
        "kind": pilot_record["kind"],
        "status": pilot_record["status"],
        "record": copy.deepcopy(pilot_record),
    }


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
    pilot = next(item for item in MODULE._frozen_active_prerequisites()[1]["observations"] if item["id"] == capture_id)
    value = _value(schedule)
    working = 1000 + int(value * 10)
    private = 5000 if scenario == "agriculture-active" else 500 + int(value * 10)
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
        "archives": copy.deepcopy(pilot["native_result"]["archives"]),
        "seed": {
            "source_path": capture["active_seed"]["path"],
            "source_sha256": capture["active_seed"]["sha256"],
            "owned_leaf": "fresh-owned-active-seed.zip",
            "owned_path": f"D:/owned/{schedule['id']}/input/fresh-owned-active-seed.zip",
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
            "stdout": "process-1.stdout.txt",
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
            "fixture_log": f"D:/owned/{schedule['id']}/write-data/factorio-current.log",
            "fixture_log_sha256": "D" * 64,
            "stdout": f"D:/owned/{schedule['id']}/process-1.stdout.txt",
            "stdout_sha256": "A" * 64,
        },
        "library_control_restoration": {
            "status": "restored-direct-library-controls",
            "profile_sha256": profile["sha256"],
            "dependency_payload_bytes_copied": 0,
            "archive_links_created": 0,
            "archive_extractions": 0,
            "selected": copy.deepcopy(pilot["native_result"]["library_control_restoration"]["selected"]),
        },
        "performance_acceptance": False,
        "release_qualification": False,
    }


def _result(plan: dict[str, object]) -> tuple[dict[str, object], str]:
    plan_sha = MODULE.PLAN_SHA256
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
    capture, _ = MODULE._frozen_active_prerequisites()
    binding_contracts = MODULE._active_binding_contracts(capture)
    bindings = {
        identifier: {
            "engine": {"path": "D:/owned/factorio/bin/x64/factorio.exe", "version": "2.1.23", "sha256": MODULE.ENGINE_SHA256},
            "library": {"path": "D:/owned/factorio/mods"},
            "profile": {"path": "D:/owned/pinned-source/profile.json", "sha256": fields["profile_sha256"]},
            "archives": fields["archives"],
            "seed": {"path": "D:/owned/active-seeds/" + identifier + ".zip", "sha256": fields["seed_sha256"], "bytes": fields["seed_bytes"]},
        }
        for identifier, fields in binding_contracts.items()
    }
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
        "bindings": bindings,
        "native_launches": 0,
        "performance_qualification": False,
        "release_qualification": False,
    })


class RuntimeBenchmarkAnalysisTests(unittest.TestCase):
    def test_actual_r06_capsule_replays_exact_analysis_through_hardened_reader(self) -> None:
        capsule_path = ROOT / "spec/evidence/runtime-active-r06-observation-analysis-receipts.json.gz"
        payload = capsule_path.read_bytes()
        self.assertEqual(_hash(payload), "7DCC75B907377193FF08C88C3BD6A26469FB7D00031B3E454AC9142B14EB4CEE")
        capsule = json.loads(gzip.decompress(payload))
        files: dict[str, bytes] = {}
        for row in capsule["files"]:
            value = base64.b64decode(row["base64"], validate=True)
            self.assertEqual(len(value), row["bytes"])
            self.assertEqual(_hash(value), row["sha256"])
            self.assertNotIn(row["path"], files)
            files[row["path"]] = value
        self.assertEqual(len(files), 9)
        raw = files["original/runtime-benchmark-active-observed.json"]
        self.assertEqual(_hash(raw), "F231BD7AB5167101DDD0215D05B0CF397338F3CEBC236795D89FC0B42EF3B2F3")
        expected = files["derived/analysis-result.json"]
        self.assertEqual(_hash(expected), "8838D3D71129876B44598B2800DDC2271F0CA326F38A5E5FEDBC554577333A43")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / "plan.json"
            result = root / "runtime-benchmark-active-observed.json"
            sidecar = root / "runtime-benchmark-active-prepared.json"
            output = root / "analysis.json"
            plan.write_bytes(files["original/runtime-benchmark-active-plan-r06.json"])
            result.write_bytes(raw)
            sidecar.write_bytes(files["original/runtime-benchmark-active-prepared.json"])
            completed = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan),
                 "--expected-plan-sha256", MODULE.PLAN_SHA256, "--result", str(result),
                 "--expected-result-sha256", _hash(raw), "--output", str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(output.read_bytes(), expected)
        analysis = json.loads(expected)
        self.assertEqual(analysis["analysis_verdict"]["status"], "within-predeclared-limits")
        self.assertFalse(analysis["claims"]["release_qualification"])

    def test_accepts_exact_frozen_r06_plan_metric_labels(self) -> None:
        payload = (ROOT / "spec/evidence/runtime-benchmark-active-plan-r06.json").read_bytes()
        self.assertEqual(_hash(payload), MODULE.PLAN_SHA256)
        plan = json.loads(payload)
        contract = MODULE._validate_plan(plan, MODULE.PLAN_SHA256)
        self.assertEqual(len(contract["profiles"]), 8)
        self.assertEqual(len(contract["helpers"]), 12)
        wrong_label = copy.deepcopy(plan)
        wrong_label["comparison_rules"]["agriculture_within_arm_increment_128_minus_1"]["metrics"][0] = "engine_reported_average_milliseconds_per_tick"
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "agriculture increment metrics"):
            MODULE._validate_plan(wrong_label, MODULE.PLAN_SHA256)

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
        self.assertEqual(_hash(plan_bytes), MODULE.PLAN_SHA256)
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
        frozen_capture, frozen_pilot = MODULE._frozen_active_prerequisites()
        captures = MODULE._validate_capture_reference(capture_reference, plan_sha, MODULE._profiles(plan), frozen_capture)
        pilot_reference = {
            "path": "original/active-marker-pilots.json",
            "sha256": MODULE.MARKER_PILOT_SHA256,
            "kind": pilot["kind"],
            "status": pilot["status"],
            "record": pilot,
        }
        MODULE._validate_pilot_reference(pilot_reference, plan_sha, capture_reference, captures, frozen_pilot)
        MODULE._validate_process_memory(pilot["observations"][0]["native_result"]["process_memory"], pilot["observations"][0]["native_result"]["native_process"])

    def test_accepts_only_producer_datetime_zero_elision_in_the_frozen_pilot(self) -> None:
        payload = _accepted_pilot_payload()
        self.assertEqual(_hash(payload), MODULE.MARKER_PILOT_SHA256)
        frozen_pilot = json.loads(payload)
        command = (
            "$ErrorActionPreference = 'Stop'; "
            "[Console]::InputEncoding = [Text.UTF8Encoding]::new($false); "
            "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); "
            "$text = [Console]::In.ReadToEnd(); $text | ConvertFrom-Json | ConvertTo-Json -Depth 50"
        )
        roundtrip = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", command],
            input=payload,
            cwd=ROOT,
            capture_output=True,
            check=False,
        )
        self.assertEqual(roundtrip.returncode, 0, roundtrip.stderr.decode("utf-8", errors="replace"))
        producer_pilot = json.loads(roundtrip.stdout)
        original_times = _pilot_start_utc_values(frozen_pilot)
        producer_times = _pilot_start_utc_values(producer_pilot)
        self.assertEqual(len(original_times), 102)
        changed = [(before, after) for before, after in zip(original_times, producer_times, strict=True) if before != after]
        self.assertEqual(len(changed), 11)
        for before, after in changed:
            self.assertTrue(before.endswith("0Z"))
            self.assertFalse(after.endswith("0Z"))
            self.assertEqual(MODULE._canonical_pilot_start_utc(before, "before"), MODULE._canonical_pilot_start_utc(after, "after"))
        plan = _plan()
        capture_reference, pilot_reference = _capture_and_pilot(plan, MODULE.PLAN_SHA256)
        pilot_reference["record"] = producer_pilot
        frozen_capture, expected_pilot = MODULE._frozen_active_prerequisites()
        captures = MODULE._validate_capture_reference(capture_reference, MODULE.PLAN_SHA256, MODULE._profiles(plan), frozen_capture)
        MODULE._validate_pilot_reference(pilot_reference, MODULE.PLAN_SHA256, capture_reference, captures, expected_pilot)

        same_instant = copy.deepcopy(frozen_pilot)
        target = next(
            row
            for observation in same_instant["observations"]
            for row in observation["native_result"]["process_memory"]["observations"]
            if row["start_utc"].endswith("0Z")
        )
        target["start_utc"] = target["start_utc"][:-2] + "Z"
        MODULE._same_pilot_record(same_instant, frozen_pilot, "marker pilot record")

        changed_instant = copy.deepcopy(frozen_pilot)
        changed_target = next(
            row
            for observation in changed_instant["observations"]
            for row in observation["native_result"]["process_memory"]["observations"]
            if row["start_utc"].endswith("0Z")
        )
        changed_target["start_utc"] = changed_target["start_utc"][:-2] + "1Z"
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "marker pilot record differs"):
            MODULE._same_pilot_record(changed_instant, frozen_pilot, "marker pilot record")
        non_time = copy.deepcopy(frozen_pilot)
        non_time["observations"][0]["complete_marker"]["status"] = "altered"
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "marker pilot record differs"):
            MODULE._same_pilot_record(non_time, frozen_pilot, "marker pilot record")

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

    def test_refuses_posthoc_profile_or_helper_plan_with_its_new_caller_hash(self) -> None:
        plan = _plan()
        result, _ = _result(plan)
        mutations: dict[str, callable] = {
            "profile": lambda item: item["active_fixture_contract"]["repair"]["profiles"][0].__setitem__("sha256", "0" * 64),
            "helper": lambda item: item["public_harness"]["git_blob_sha256"][0].__setitem__("sha256", "0" * 64),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                changed = copy.deepcopy(plan)
                mutate(changed)
                changed_sha = _hash(_encode(changed))
                self.assertNotEqual(changed_sha, MODULE.PLAN_SHA256)
                with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "raw R06 plan SHA-256"):
                    MODULE.analyze(changed, changed_sha, result, _hash(_encode(result)))

    def test_refuses_schedule_seed_pilot_restoration_and_identity_opponents(self) -> None:
        plan = _plan()
        result, plan_sha = _result(plan)

        def add_mixed_memory_identity(item: dict[str, object]) -> None:
            observation = item["observations"][0]
            duplicate = copy.deepcopy(observation["process_memory"]["observations"][0])
            duplicate["pid"] = 101
            observation["process_memory"]["observations"].append(duplicate)
            observation["native_process"]["sampled_observation_count"] = 2

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
            "cross-sample-stdout": lambda item: item["observations"][0]["physical_markers"].__setitem__("stdout", "D:/owned/another-sample/process-1.stdout.txt"),
            "relative-physical-stdout": lambda item: item["observations"][0]["physical_markers"].__setitem__("stdout", "process-1.stdout.txt"),
            "escaped-native-stdout": lambda item: item["observations"][0]["native_process"].__setitem__("stdout", "../process-1.stdout.txt"),
            "cross-sample-fixture-log": lambda item: item["observations"][0]["physical_markers"].__setitem__("fixture_log", "D:/owned/another-sample/write-data/factorio-current.log"),
            "cross-sample-owned-seed": lambda item: item["observations"][0]["seed"].__setitem__("owned_path", "D:/owned/another-sample/input/fresh-owned-active-seed.zip"),
            "extra-sample-archive": lambda item: item["observations"][0]["archives"].__setitem__("unreviewed_0.1.0.zip", "0" * 64),
            "extra-restored-selection": lambda item: item["observations"][0]["library_control_restoration"]["selected"].append(copy.deepcopy(item["observations"][0]["library_control_restoration"]["selected"][0])),
            "mixed-process-memory-identity": add_mixed_memory_identity,
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
            plan_bytes = (ROOT / MODULE.PLAN_PATH).read_bytes()
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
            bad_binding = json.loads(prepared_bytes)
            bad_binding["bindings"]["repair-published"]["archives"]["more-infinite-research_4.7.21002.zip"] = "0" * 64
            bad_binding_bytes = _encode(bad_binding)
            result["prepared_inputs_sha256"] = _hash(bad_binding_bytes)
            bad_binding_result_bytes = _encode(result)
            result_path.write_bytes(bad_binding_result_bytes)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(bad_binding_bytes)
            binding_refusal = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", _hash(bad_binding_result_bytes), "--output", str(root / "bad-binding.json")],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(binding_refusal.returncode, 1)
            self.assertIn("prepared inputs sidecar binding archive closure differs", binding_refusal.stderr)
            for argument in ("--expected-plan-sha256", "--expected-result-sha256"):
                failed = subprocess.run(
                    [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", "0" * 64 if argument == "--expected-plan-sha256" else _hash(plan_bytes), "--result", str(result_path), "--expected-result-sha256", "0" * 64 if argument == "--expected-result-sha256" else _hash(bad_binding_result_bytes), "--output", str(root / (argument[2:] + ".json"))],
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

    def test_cli_refuses_changed_profile_or_helper_with_matching_caller_plan_hash(self) -> None:
        original = _plan()
        mutations: dict[str, callable] = {
            "profile": lambda item: item["active_fixture_contract"]["repair"]["profiles"][0].__setitem__("sha256", "0" * 64),
            "helper": lambda item: item["public_harness"]["git_blob_sha256"][0].__setitem__("sha256", "0" * 64),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for label, mutate in mutations.items():
                with self.subTest(label=label):
                    plan = copy.deepcopy(original)
                    mutate(plan)
                    plan_bytes = _encode(plan)
                    plan_sha = _hash(plan_bytes)
                    result, _ = _result(original)
                    result["plan"]["sha256"] = plan_sha
                    prepared_bytes = _prepared_inputs(result)
                    result["prepared_inputs_sha256"] = _hash(prepared_bytes)
                    result_bytes = _encode(result)
                    plan_path = root / (label + "-plan.json")
                    result_path = root / (label + "-result.json")
                    output_path = root / (label + "-analysis.json")
                    plan_path.write_bytes(plan_bytes)
                    result_path.write_bytes(result_bytes)
                    (root / "runtime-benchmark-active-prepared.json").write_bytes(prepared_bytes)
                    refused = subprocess.run(
                        [sys.executable, str(TOOL_PATH), "--raw-plan", str(plan_path), "--expected-plan-sha256", plan_sha, "--result", str(result_path), "--expected-result-sha256", _hash(result_bytes), "--output", str(output_path)],
                        cwd=ROOT,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(refused.returncode, 1)
                    self.assertIn("expected R06 plan SHA-256 differs", refused.stderr)


class Current38CRuntimeBenchmarkAnalysisTests(unittest.TestCase):
    def setUp(self) -> None:
        MODULE.select_cohort("current38c")

    def tearDown(self) -> None:
        MODULE.select_cohort("r06")

    def test_actual_current_capsule_replays_exact_complete_analysis(self) -> None:
        payload = (ROOT / "spec/evidence/runtime-current38c-observation-analysis-receipts-r01.json.gz").read_bytes()
        self.assertEqual(_hash(payload), "D499884F0FE7A548F8F391EE1DCA0874F7269E0030383143E391DD9686FD3FEF")
        files: dict[str, bytes] = {}
        for row in json.loads(gzip.decompress(payload))["files"]:
            raw = base64.b64decode(row["base64"], validate=True)
            self.assertEqual(len(raw), row["bytes"])
            self.assertEqual(_hash(raw), row["sha256"])
            self.assertNotIn(row["path"], files)
            files[row["path"]] = raw
        self.assertEqual(len(files), 145)
        observed = files["original/runtime-benchmark-active-observed.json"]
        expected = files["derived/analysis-result.json"]
        self.assertEqual(_hash(observed), "78F2D9EACFC7588B725DDA427485724FF34405026997B6325CEDF38B7C49963D")
        self.assertEqual(_hash(expected), "29D6093F76C826E8FC7D72C160008F9A173BFC4CF56B9AE7B4D45391AB6C89DA")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan, result, output = root / "plan.json", root / "runtime-benchmark-active-observed.json", root / "analysis.json"
            plan.write_bytes(files["original/runtime-current38c-active-plan-r01.json"])
            result.write_bytes(observed)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(files["original/runtime-benchmark-active-prepared.json"])
            completed = subprocess.run(
                [sys.executable, str(TOOL_PATH), "--cohort", "current38c", "--raw-plan", str(plan),
                 "--expected-plan-sha256", MODULE.PLAN_SHA256, "--result", str(result),
                 "--expected-result-sha256", _hash(observed), "--output", str(output)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(output.read_bytes(), expected)
        analysis = json.loads(expected)
        self.assertEqual(analysis["analysis_verdict"]["status"], "within-predeclared-limits")
        self.assertFalse(analysis["claims"]["release_qualification"])

    def test_current_plan_and_real_unscored_prerequisites_have_exact_closure(self) -> None:
        plan = _plan()
        contract = MODULE._validate_plan(plan, MODULE.PLAN_SHA256)
        self.assertEqual(len(contract["profiles"]), 8)
        self.assertEqual(len(contract["helpers"]), 12)
        capture, pilot = MODULE._frozen_active_prerequisites()
        self.assertEqual(len(capture["captures"]), 8)
        self.assertEqual(len(pilot["observations"]), 8)
        self.assertEqual(pilot["schedule_launches"], 0)
        self.assertFalse(pilot["performance_acceptance"])
        self.assertFalse(pilot["release_qualification"])
        for field, mutate in {
            "engine": lambda p: p["engine"].__setitem__("sha256", MODULE._R06_BINDINGS["ENGINE_SHA256"]),
            "archive": lambda p: p["candidate"]["f210_archive"].__setitem__("sha256", MODULE._R06_BINDINGS["CANDIDATE_SHA256"]),
            "schedule": lambda p: p["schedule"].__setitem__("total_launches", 67),
        }.items():
            with self.subTest(field=field):
                bad = copy.deepcopy(plan)
                mutate(bad)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    MODULE._validate_plan(bad, MODULE.PLAN_SHA256)

    def test_synthetic_current_scores_use_real_prerequisites_and_original_rules(self) -> None:
        # These values exercise the reader; they are not native observations.
        plan = _plan()
        result, plan_sha = _result(plan)
        analysis = MODULE.analyze(plan, plan_sha, result, _hash(_encode(result)))
        self.assertEqual(analysis["kind"], "MIR5RuntimeBenchmarkActiveCurrent38CAnalysisV1")
        self.assertEqual(analysis["analysis_verdict"]["status"], "within-predeclared-limits")
        self.assertEqual(len(result["observations"]), 68)
        self.assertFalse(analysis["claims"]["release_qualification"])
        for label, mutate in {
            "missing-score": lambda r: r["observations"].pop(),
            "old-capture": lambda r: r["active_seed_capture"].__setitem__("sha256", MODULE._R06_BINDINGS["ACTIVE_SEED_CAPTURE_SHA256"]),
            "old-pilot": lambda r: r["unscored_marker_pilot"].__setitem__("sha256", MODULE._R06_BINDINGS["MARKER_PILOT_SHA256"]),
            "incomplete-work": lambda r: r["observations"][0]["physical_markers"]["complete"]["witnesses"].__setitem__("pending_physical_work", True),
        }.items():
            with self.subTest(label=label):
                bad = copy.deepcopy(result)
                mutate(bad)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    MODULE.analyze(plan, plan_sha, bad, _hash(_encode(bad)))
        # Crossing a declared limit must report failure rather than relax it.
        for row in result["observations"]:
            if row["arm"] == "candidate":
                row["timing"]["average_milliseconds_per_tick"] = 1000.0
        failed = MODULE.analyze(plan, plan_sha, result, _hash(_encode(result)))
        self.assertEqual(failed["analysis_verdict"]["status"], "outside-predeclared-limits")

    def test_current_cli_requires_explicit_cohort_and_bound_sidecar(self) -> None:
        plan = _plan()
        result, plan_sha = _result(plan)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw_plan = root / "plan.json"
            raw_result = root / "runtime-benchmark-active-observed.json"
            raw_plan.write_bytes((ROOT / MODULE.PLAN_PATH).read_bytes())
            prepared = _prepared_inputs(result)
            (root / "runtime-benchmark-active-prepared.json").write_bytes(prepared)
            result["prepared_inputs_sha256"] = _hash(prepared)
            raw_result.write_bytes(_encode(result))
            arguments = [sys.executable, str(TOOL_PATH), "--raw-plan", str(raw_plan),
                         "--expected-plan-sha256", plan_sha, "--result", str(raw_result),
                         "--expected-result-sha256", _hash(raw_result.read_bytes())]
            refused = subprocess.run(arguments + ["--output", str(root / "default.json")], capture_output=True, text=True, check=False)
            self.assertEqual(refused.returncode, 1)
            self.assertFalse((root / "default.json").exists())
            accepted = subprocess.run(arguments + ["--cohort", "current38c", "--output", str(root / "current.json")], capture_output=True, text=True, check=False)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertEqual(json.loads((root / "current.json").read_bytes())["status"], "complete-predeclared-current38c-analysis")
            (root / "runtime-benchmark-active-prepared.json").write_bytes(b"{}\n")
            corrupt = subprocess.run(arguments + ["--cohort", "current38c", "--output", str(root / "corrupt.json")], capture_output=True, text=True, check=False)
            self.assertEqual(corrupt.returncode, 1)
            self.assertFalse((root / "corrupt.json").exists())

    def test_unknown_cohort_cannot_change_selected_identity(self) -> None:
        previous = MODULE.PLAN_SHA256
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "unknown frozen"):
            MODULE.select_cohort("latest")
        self.assertEqual(MODULE.PLAN_SHA256, previous)


class Current505GroundRuntimeBenchmarkAnalysisTests(unittest.TestCase):
    def setUp(self) -> None:
        MODULE.select_cohort("current505-ground")

    def tearDown(self) -> None:
        MODULE.select_cohort("r06")

    def test_exact_current_ground_plan_and_original_physical_receipts_are_admitted(self) -> None:
        raw = (ROOT / "spec/evidence/runtime505-active-plan-r02.json").read_bytes()
        plan = json.loads(raw)
        MODULE._validate_plan(plan, _hash(raw))
        profiles = MODULE._profiles(plan)
        self.assertEqual(len(profiles), 8)
        expected_paths = {row["path"] for group in plan["active_fixture_contract"].values() for row in group["profiles"]}
        self.assertEqual({row["path"] for row in profiles.values()}, expected_paths)
        capture, pilot = MODULE._frozen_active_prerequisites()
        self.assertEqual(len(capture["captures"]), 8)
        self.assertEqual(len(pilot["observations"]), 8)
        self.assertEqual(pilot["schedule_launches"], 0)
        self.assertEqual(MODULE.CANDIDATE_LEAF, "more-infinite-research_5.0.21005.zip")
        self.assertFalse(pilot["performance_acceptance"])

    def test_other_plan_package_or_profile_identities_cannot_be_relabelled_current505(self) -> None:
        for name in ("runtime-benchmark-active-plan-r06.json", "runtime-current38c-active-plan-r01.json", "runtime505-active-plan-r01.json"):
            with self.subTest(name=name):
                raw = (ROOT / "spec/evidence" / name).read_bytes()
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    MODULE._validate_plan(json.loads(raw), _hash(raw))
        raw = (ROOT / "spec/evidence/runtime505-active-plan-r02.json").read_bytes()
        plan = json.loads(raw)
        plan["candidate"]["f210_archive"]["name"] = "more-infinite-research_5.0.21000.zip"
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "archive name"):
            MODULE._validate_plan(plan, _hash(raw))
        plan = json.loads(raw)
        plan["active_fixture_contract"]["agriculture"]["profiles"][0]["path"] = "tests/profiles/runtime505-agriculture-published-128-f210-2123.json"
        with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "profile identity"):
            MODULE._profiles(plan)

    def test_old_cohort_selection_restores_its_original_package_identity(self) -> None:
        MODULE.select_cohort("current38c")
        self.assertEqual(MODULE.CANDIDATE_LEAF, "more-infinite-research_5.0.21000.zip")
        MODULE.select_cohort("current505-ground")
        self.assertEqual(MODULE.CANDIDATE_LEAF, "more-infinite-research_5.0.21005.zip")
        MODULE.select_cohort("r06")
        self.assertEqual(MODULE.CANDIDATE_LEAF, "more-infinite-research_5.0.21000.zip")



class Current510MixedRuntimeBenchmarkAnalysisTests(unittest.TestCase):
    def setUp(self) -> None:
        MODULE.select_cohort("current510-mixed")
        self.plan = _plan()
        self.profiles = MODULE._validate_plan(self.plan, MODULE.PLAN_SHA256)["profiles"]
        self.frozen = MODULE._frozen_mixed_prerequisites()
        self.old_plan = json.loads((ROOT / "spec/evidence/runtime505-active-plan-r02.json").read_bytes())
        self.old_capture = self.frozen["original/active-seed-captures.json"]
        self.old_pilot = self.frozen["original/active-marker-pilots.json"]
        self.origins = self.frozen["candidate/original-origins.json"]
        self.pilot = self.frozen["candidate/formal-marker-pilots.json"]
        helpers = [{"path": row["path"], "raw_git_sha256": row["sha256"], "executed_sha256": row["sha256"], "bytes": 1}
                   for row in self.old_plan["public_harness"]["git_blob_sha256"]]
        self.mixed = {
            "published": {
                "plan": {"plan": self.old_plan, "sha256": MODULE._CURRENT505_GROUND_BINDINGS["PLAN_SHA256"],
                         "source_revision": MODULE._CURRENT505_GROUND_BINDINGS["PLAN_REVISION"], "active_cohort": "current505-ground-r02"},
                "raw_helper_stage": "D:/synthetic/old-stage", "raw_helpers": helpers,
                "capture": {"path": "D:/synthetic/old-capture.json", "sha256": MODULE._CURRENT505_GROUND_BINDINGS["ACTIVE_SEED_CAPTURE_SHA256"], "record": self.old_capture},
                "pilot": {"path": "D:/synthetic/old-pilot.json", "sha256": MODULE._CURRENT505_GROUND_BINDINGS["MARKER_PILOT_SHA256"], "record": self.old_pilot},
            },
            "candidate": {
                "origins": {"path": "D:/synthetic/current-origins.json", "sha256": MODULE._CURRENT510_ORIGINS_SHA256, "record": self.origins},
                "pilot": {"path": "D:/synthetic/current-pilot.json", "sha256": MODULE._CURRENT510_PILOT_SHA256, "record": self.pilot},
            },
        }
        self.old_by_native = {row["native_result_path"]: row for row in self.old_capture["captures"] if row["arm"] == "published"}
        self.original_read_json = MODULE._read_json

    def tearDown(self) -> None:
        MODULE.select_cohort("r06")

    def _read_synthetic(self, path, limit, label):
        if label != "published native result":
            return self.original_read_json(path, limit, label)
        row = self.old_by_native[str(path)]
        return ({"source_head": MODULE._CURRENT505_GROUND_BINDINGS["PLAN_SOURCE"],
                 "status": "passed-private-native-active-seed-preparation",
                 "mir_archive": {"path": "D:/synthetic/player.zip", "sha256": MODULE.PUBLISHED_SHA256},
                 "engine": {"path": "D:/synthetic/factorio.exe", "sha256": MODULE.ENGINE_SHA256},
                 "profile": {"sha256": row["profile"]["sha256"]},
                 "active_seed": {"sha256": row["active_seed"]["sha256"]},
                 "active_preparation": {"marker": row["prepared_marker"]}}, "A" * 64)

    def _patches(self):
        return (
            mock.patch.object(MODULE, "_verified_file", side_effect=lambda path, digest, label, size=None: Path(str(path))),
            mock.patch.object(MODULE, "_validate_current510_origin", side_effect=lambda row, expected, profile, plan: row),
            mock.patch.object(MODULE, "_verify_pilot_files"),
            mock.patch.object(MODULE, "_read_json", side_effect=self._read_synthetic),
            mock.patch.object(MODULE, "_validate_fixture_members"),
        )

    def _validated(self, mixed=None):
        with self._patches()[0], self._patches()[1], self._patches()[2], self._patches()[3], self._patches()[4]:
            return MODULE._validate_current510_mixed({"mixed_prerequisites": mixed or self.mixed}, self.profiles)

    def test_frozen_plan_and_capsule_bind_distinct_original_identities(self) -> None:
        self.assertEqual(len(self.profiles), 8)
        self.assertEqual(len(self.frozen), 4)
        captures, pilots, _ = self._validated()
        self.assertEqual((len(captures), len(pilots)), (8, 8))
        for change in (lambda p: p["candidate"]["f210_archive"].__setitem__("sha256", "0" * 64),
                       lambda p: p["schedule"].__setitem__("total_launches", 67),
                       lambda p: p["active_fixture_contract"]["repair"]["profiles"].append({})):
            changed = copy.deepcopy(self.plan)
            change(changed)
            with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                MODULE._validate_plan(changed, MODULE.PLAN_SHA256)
        self.assertEqual(MODULE.KIND, MODULE._CURRENT510_BINDINGS["KIND"])

    def test_mixed_prerequisite_opponents_are_refused_without_metrics(self) -> None:
        for label, mutate in {
            "old-capture-hash": lambda x: x["published"]["capture"].__setitem__("sha256", "0" * 64),
            "old-pilot-record": lambda x: x["published"]["pilot"]["record"]["observations"].pop(),
            "old-harness": lambda x: x["published"]["raw_helpers"][0].__setitem__("executed_sha256", "0" * 64),
            "new-origin-hash": lambda x: x["candidate"]["origins"].__setitem__("sha256", "0" * 64),
            "new-source": lambda x: x["candidate"]["origins"]["record"]["rows"][0]["source_harness"].__setitem__("commit", "0" * 40),
            "new-pilot-count": lambda x: x["candidate"]["pilot"]["record"]["observations"].pop(),
            "new-pilot-controller": lambda x: x["candidate"]["pilot"]["record"]["private_controller"].__setitem__("revision", "0" * 40),
        }.items():
            with self.subTest(label=label):
                altered = copy.deepcopy(self.mixed)
                mutate(altered)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    self._validated(altered)

    def _synthetic_result(self):
        captures, pilots, _ = self._validated()
        provenance = MODULE._current510_row_provenance(captures)
        for row in MODULE._active_rows():
            if row["arm"] != "published":
                scenario = "repair-active" if row["kind"] == "repair-stress" else "agriculture-active"
                provenance[row["id"]]["canonical_profile_sha256"] = self.profiles[(scenario, row["tier"], row["arm"])]["sha256"]
        schedule = _independent_schedule()
        observations = []
        MODULE.select_cohort("current505-ground")
        try:
            old_ref = {"record": self.old_capture}
            for selected in schedule:
                sample = _observation(self.old_plan, selected, old_ref)
                scenario, tier, arm = selected["scenario"], selected["tier"], selected["arm"]
                identifier = "repair-" + arm if scenario == "repair-active" else f"agriculture-{arm}-{tier}"
                profile = self.profiles[(scenario, tier, arm)]
                seed = captures[identifier]["active_seed"]
                sample["profile"] = {"path": "D:/owned/pinned-source/" + profile["path"], "sha256": profile["sha256"]}
                sample["archives"] = copy.deepcopy(pilots[identifier]["archives"])
                sample["seed"].update({"source_path": seed["path"], "source_sha256": seed["sha256"], "owned_sha256": seed["sha256"], "bytes": seed["bytes"]})
                for part in ("source", "owned"):
                    sample["seed_integrity_after_sample"][part].update({"expected_sha256": seed["sha256"], "actual_sha256": seed["sha256"]})
                sample["library_control_restoration"]["profile_sha256"] = profile["sha256"]
                sample["library_control_restoration"]["selected"] = copy.deepcopy(pilots[identifier]["library_control_restoration"]["selected"])
                sample["input_provenance"] = copy.deepcopy(provenance[identifier])
                observations.append(sample)
        finally:
            MODULE.select_cohort("current510-mixed")
        return {
            "schema": 1, "kind": MODULE.RESULT_KIND, "status": "observed-not-performance-accepted",
            "plan": {"path": MODULE.PLAN_PATH, "source_revision": MODULE.PLAN_REVISION, "sha256": MODULE.PLAN_SHA256},
            "private_controller": {"revision": MODULE._CURRENT510_CONTROLLER_REVISION, "path": "Invoke-RuntimeBenchmark.ps1",
                                   "raw_git_sha256": MODULE._CURRENT510_CONTROLLER_SHA256, "executed_sha256": MODULE._CURRENT510_CONTROLLER_SHA256,
                                   "executed_matches_raw_git": True},
            "raw_helper_source": {"revision": MODULE.PLAN_SOURCE, "stage_checkout_revision": MODULE.PLAN_REVISION,
                                  "members": [{"path": row["path"], "raw_git_sha256": row["sha256"], "executed_sha256": row["sha256"], "bytes": 1}
                                              for row in self.plan["public_harness"]["git_blob_sha256"]]},
            "prepared_inputs_path": "runtime-benchmark-active-prepared.json", "prepared_inputs_sha256": "C" * 64,
            "mixed_prerequisites": copy.deepcopy(self.mixed), "row_provenance": provenance,
            "schedule": schedule, "observations": observations, "performance_qualification": False, "release_qualification": False,
        }

    def test_synthetic_68_scores_keep_original_math_and_refuse_mixed_opponents(self) -> None:
        result = self._synthetic_result()
        def analyze(value):
            patches = self._patches()
            with patches[0], patches[1], patches[2], patches[3], patches[4], mock.patch.object(MODULE, "_validate_current510_custody"), mock.patch.object(MODULE, "_verify_current510_controller_file"):
                return MODULE.analyze(self.plan, MODULE.PLAN_SHA256, value, _hash(_encode(value)))
        analysis = analyze(result)
        self.assertEqual(analysis["kind"], "MIR510MixedActiveRuntimeAnalysisV1")
        self.assertEqual(len(analysis["schedule"]), 68)
        self.assertEqual(analysis["analysis_verdict"]["status"], "within-predeclared-limits")
        self.assertFalse(analysis["claims"]["release_qualification"])
        for label, mutate in {
            "missing-score": lambda r: r["observations"].pop(),
            "controller-head": lambda r: r["private_controller"].__setitem__("revision", "0" * 40),
            "controller-bytes": lambda r: r["private_controller"].__setitem__("raw_git_sha256", "0" * 64),
            "stage-head": lambda r: r["raw_helper_source"].__setitem__("stage_checkout_revision", "0" * 40),
            "old-origin": lambda r: r["row_provenance"]["repair-published"].__setitem__("source_harness", "0" * 40),
            "current-origin": lambda r: r["row_provenance"]["repair-candidate"].__setitem__("original_profile_sha256", "0" * 64),
            "sample-provenance": lambda r: r["observations"][0]["input_provenance"].__setitem__("pilot_receipt_sha256", "0" * 64),
            "sample-fixture": lambda r: r["observations"][0]["archives"].__setitem__("unexpected.zip", "A" * 64),
            "sample-seed": lambda r: r["observations"][0]["seed"].__setitem__("source_sha256", "A" * 64),
            "sample-physical": lambda r: r["observations"][0]["physical_markers"]["complete"]["witnesses"].__setitem__("pending_physical_work", True),
        }.items():
            with self.subTest(label=label):
                altered = copy.deepcopy(result)
                mutate(altered)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    analyze(altered)
        for row in result["observations"]:
            if row["arm"] == "candidate":
                row["timing"]["average_milliseconds_per_tick"] = 1000.0
        self.assertEqual(analyze(result)["analysis_verdict"]["status"], "outside-predeclared-limits")

    def test_current_controller_body_requires_explicit_hash_bound_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            controller = Path(directory) / "synthetic-controller.ps1"
            controller.write_bytes(b"independent synthetic committed controller")
            with mock.patch.object(MODULE, "_CURRENT510_CONTROLLER_SHA256", _hash(controller.read_bytes())):
                MODULE._verify_current510_controller_file(controller)
                with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "explicit retained controller"):
                    MODULE._verify_current510_controller_file(None)
                controller.write_bytes(b"different bytes")
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    MODULE._verify_current510_controller_file(controller)

    def test_cli_requires_explicit_current_controller_before_reading_result(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            completed = subprocess.run([sys.executable, str(TOOL_PATH), "--cohort", "current510-mixed",
                "--raw-plan", str(root / "absent-plan.json"), "--expected-plan-sha256", MODULE.PLAN_SHA256,
                "--result", str(root / "absent-result.json"), "--expected-result-sha256", "A" * 64,
                "--output", str(root / "output.json")], capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 1)
            self.assertIn("explicit retained controller", completed.stderr)
            self.assertFalse((root / "output.json").exists())

    def test_fixture_archive_members_are_exact_and_independent(self) -> None:
        name, version = "mir-fixture-mir5-repair-stress", "0.2.1"
        control, metadata = b"synthetic independent control", b"synthetic independent metadata"
        plan = {"active_fixture_contract": {"repair": {"fixture_source_members": [
            {"fixture": "repair-stress", "member": "control.lua", "sha256": _hash(control)},
            {"fixture": "repair-candidate", "member": "info.json", "sha256": _hash(metadata)},
        ]}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / (name + "_" + version + ".zip")
            fixture = {"name": name, "version": version, "path": str(path)}
            def write(control_body=control, extra=False):
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr(f"{name}_{version}/control.lua", control_body)
                    archive.writestr(f"{name}_{version}/info.json", metadata)
                    if extra:
                        archive.writestr(f"{name}_{version}/unexpected.lua", b"extra")
            write()
            MODULE._validate_fixture_members(fixture, plan, "repair", "candidate", 0)
            write(b"different")
            with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                MODULE._validate_fixture_members(fixture, plan, "repair", "candidate", 0)
            write(extra=True)
            with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                MODULE._validate_fixture_members(fixture, plan, "repair", "candidate", 0)

    def test_original_profile_normalization_and_native_identity_with_synthetic_files(self) -> None:
        origin = copy.deepcopy(self.origins["rows"][0])
        expected = next(row for row in MODULE._active_rows() if row["id"] == origin["id"])
        profile = self.profiles[("repair-active", 0, "candidate")]
        canonical = json.loads((ROOT / profile["path"]).read_bytes())
        raw_harness = b"independent synthetic native harness"
        native = {
            "source_head": origin["source_harness"]["commit"], "source_dirty": False,
            "harness_sha256": _hash(raw_harness), "status": "passed-private-native-active-seed-preparation",
            "profile": copy.deepcopy(origin["profile"]), "mir_archive": copy.deepcopy(origin["mir_archive"]),
            "engine": copy.deepcopy(origin["engine"]), "active_seed": copy.deepcopy(origin["active_seed"]),
            "library_control_restoration": {"status": "restored-direct-library-controls"},
            "active_preparation": {"marker": copy.deepcopy(origin["prepared_marker"])},
            "fixtures": [{"archive": row["path"], "sha256": row["sha256"]} for row in origin["fixtures"]],
        }
        def read_reference(ref, label):
            return canonical if label == "current510 original profile" else native
        def git_result(args, **kwargs):
            return origin["source_harness"]["tree"] + "\n" if "rev-parse" in args else raw_harness
        marker_bytes = ("[MIR5_RUNTIME_ACTIVE] " + json.dumps(origin["prepared_marker"]) + "\n").encode()
        real_bounded = MODULE._read_bounded
        def read_bounded(path, limit, label):
            return marker_bytes if label == "current510 prepared log" else real_bounded(path, limit, label)
        def validate(value):
            with mock.patch.object(MODULE, "_verified_file", side_effect=lambda path, digest, label, size=None: Path(str(path))), \
                 mock.patch.object(MODULE, "_verified_json_reference", side_effect=read_reference), \
                 mock.patch.object(MODULE.subprocess, "check_output", side_effect=git_result), \
                 mock.patch.object(MODULE, "_read_bounded", side_effect=read_bounded), \
                 mock.patch.object(MODULE, "_validate_fixture_members"):
                MODULE._validate_current510_origin(value, expected, profile, self.plan)
        validate(origin)
        for label, mutate in {
            "wrong-profile-hash": lambda r: r["profile"].__setitem__("sha256", "0" * 64),
            "wrong-source-tree": lambda r: r["source_harness"].__setitem__("tree", "0" * 40),
            "wrong-fixture-version": lambda r: r["fixtures"][0].__setitem__("version", "0.2.0"),
            "missing-fixture": lambda r: r["fixtures"].pop(),
            "wrong-player": lambda r: r["mir_archive"].__setitem__("sha256", "0" * 64),
            "wrong-engine": lambda r: r["engine"].__setitem__("sha256", "0" * 64),
            "wrong-native-marker": lambda r: r["prepared_marker"]["witnesses"].__setitem__("initial_changed", 1),
        }.items():
            with self.subTest(label=label):
                altered = copy.deepcopy(origin)
                mutate(altered)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    validate(altered)
        with mock.patch.object(MODULE, "_verified_file", side_effect=lambda path, digest, label, size=None: Path(str(path))), \
             mock.patch.object(MODULE, "_verified_json_reference", side_effect=lambda ref, label: {**canonical, "settings_mode": "wrong"} if label == "current510 original profile" else native), \
             mock.patch.object(MODULE.subprocess, "check_output", side_effect=git_result):
            with self.assertRaisesRegex(MODULE.RuntimeBenchmarkAnalysisError, "normalized profile"):
                MODULE._validate_current510_origin(origin, expected, profile, self.plan)

    def test_mixed_prepared_sidecar_binds_all_eight_profiles_and_seeds(self) -> None:
        result = self._synthetic_result()
        captures, pilots, _ = self._validated()
        bindings = {}
        for row in MODULE._active_rows():
            scenario = "repair-active" if row["kind"] == "repair-stress" else "agriculture-active"
            profile = self.profiles[(scenario, row["tier"], row["arm"])]
            seed = captures[row["id"]]["active_seed"]
            bindings[row["id"]] = {"engine": {"version": "2.1.23", "sha256": MODULE.ENGINE_SHA256},
                "library": "D:/Projects/Factorio/testmods/2.1",
                "profile": {"path": "D:/owned/pinned-source/" + profile["path"], "sha256": profile["sha256"]},
                "archives": copy.deepcopy(pilots[row["id"]]["archives"]),
                "seed": {"path": seed["path"], "sha256": seed["sha256"], "bytes": seed["bytes"]}}
        sidecar = {"schema": 1, "kind": "MIR5ActiveRuntimeBenchmarkPreparedInputsV1",
                   "status": "validated-accepted-active-inputs-no-new-native", "native_launches": 0,
                   "performance_qualification": False, "release_qualification": False, "bindings": bindings,
                   **{key: copy.deepcopy(result[key]) for key in ("plan", "private_controller", "raw_helper_source", "mixed_prerequisites", "row_provenance", "schedule")}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def validate(value):
                payload = _encode(value)
                (root / "runtime-benchmark-active-prepared.json").write_bytes(payload)
                result["prepared_inputs_sha256"] = _hash(payload)
                patches = self._patches()
                with patches[0], patches[1], patches[2], patches[3], patches[4]:
                    MODULE._validate_prepared_inputs_sidecar(root / "runtime-benchmark-active-observed.json", result)
            validate(sidecar)
            for label, mutate in {
                "missing-binding": lambda v: v["bindings"].pop("repair-published"),
                "wrong-original-seed": lambda v: v["bindings"]["repair-published"]["seed"].__setitem__("sha256", "0" * 64),
                "wrong-candidate-profile": lambda v: v["bindings"]["repair-candidate"]["profile"].__setitem__("sha256", "0" * 64),
                "wrong-archive-closure": lambda v: v["bindings"]["repair-candidate"]["archives"].__setitem__("extra.zip", "A" * 64),
                "changed-provenance": lambda v: v["row_provenance"]["repair-candidate"].__setitem__("original_profile_sha256", "0" * 64),
            }.items():
                with self.subTest(label=label):
                    bad = copy.deepcopy(sidecar)
                    mutate(bad)
                    with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                        validate(bad)

    def test_custody_exact_closure_restoration_and_opponents(self) -> None:
        identifier = "repair-warmup-published-1"
        fixture = {"archive": "D:/original/mir-fixture-mir5-repair-stress_0.1.0.zip", "sha256": "A" * 64}
        leaf = "mir-fixture-mir5-repair-stress_0.1.0.zip"
        root = "D:/owned/run"
        record = {"schema": 1, "kind": "MIR5RuntimeBenchmark510FixtureCustodyV1", "reserved_mib": 2,
                  "body_succeeded": True, "restoration_failures": [], "fixtures": [{
                      "leaf": leaf, "source": fixture["archive"], "destination": "D:/Projects/Factorio/testmods/2.1/" + leaf,
                      "selected_sha256": fixture["sha256"], "prior_exists": True, "prior_sha256": "B" * 64,
                      "prior_bytes": 17, "snapshot": root + "/fixture-custody/" + identifier + "/prior/" + leaf,
                      "changed": True, "restoration_status": "verified", "restored_sha256": "B" * 64, "restored_bytes": 17}]}
        active = {"kind": "repair-stress", "arm": "published", "tier": 0}
        start = _marker("repair-stress", "start", "pending", _pilot_witness(active, False))
        complete = _marker("repair-stress", "complete", "passed", _pilot_witness(active, True))
        sample = {"seed": {"owned_path": root + "/pinned-source/build/tmp/active-launches/" + identifier + "/input/fresh-owned-active-seed.zip"},
                  "fixture_custody_reserve_mib": 2,
                  "fixture_custody": {"path": root + "/fixture-custody/" + identifier + "/fixture-custody-result.json", "sha256": "C" * 64, "record": record},
                  "physical_markers": {"start": start, "complete": complete, "fixture_log": root + "/fixture.log", "fixture_log_sha256": "D" * 64,
                                       "stdout": root + "/stdout.txt", "stdout_sha256": "E" * 64}}
        schedule = {"id": identifier, "scenario": "repair-active"}
        provenance = {"fixtures": [fixture]}
        journal = [{**record["fixtures"][0], "restoration_status": "pending", "restored_sha256": "", "restored_bytes": 0}]
        marker_log = ("[MIR5_RUNTIME_ACTIVE] " + json.dumps(start) + "\n[MIR5_RUNTIME_ACTIVE] " + json.dumps(complete) + "\n").encode()
        def read_bounded(path, limit, label):
            if label == "current510 custody journal":
                return _encode(journal)
            if label == "current510 custody result bytes":
                return _encode(record)
            return marker_log
        def validate(value):
            with mock.patch.object(MODULE, "_verified_json_reference", return_value=value["fixture_custody"]["record"]), \
                 mock.patch.object(MODULE, "_verified_file", side_effect=lambda path, digest, label, size=None: Path(str(path))), \
                 mock.patch.object(MODULE, "_read_bounded", side_effect=read_bounded):
                MODULE._validate_current510_custody(value, schedule, provenance)
        validate(sample)
        for label, mutate in {
            "missing-fixture": lambda s: s["fixture_custody"]["record"]["fixtures"].clear(),
            "not-restored": lambda s: s["fixture_custody"]["record"]["fixtures"][0].__setitem__("restoration_status", "failed"),
            "wrong-restore-hash": lambda s: s["fixture_custody"]["record"]["fixtures"][0].__setitem__("restored_sha256", "F" * 64),
            "wrong-destination": lambda s: s["fixture_custody"]["record"]["fixtures"][0].__setitem__("destination", "D:/other/" + leaf),
            "wrong-source": lambda s: s["fixture_custody"]["record"]["fixtures"][0].__setitem__("source", "D:/other/" + leaf),
            "no-snapshot": lambda s: s["fixture_custody"]["record"]["fixtures"][0].__setitem__("snapshot", ""),
            "over-budget": lambda s: s["fixture_custody"]["record"].__setitem__("reserved_mib", 120),
            "wrong-raw-marker": lambda s: s["physical_markers"]["complete"]["witnesses"].__setitem__("initial_changed", 255),
        }.items():
            with self.subTest(label=label):
                bad = copy.deepcopy(sample)
                mutate(bad)
                with self.assertRaises(MODULE.RuntimeBenchmarkAnalysisError):
                    validate(bad)


if __name__ == "__main__":
    unittest.main()
