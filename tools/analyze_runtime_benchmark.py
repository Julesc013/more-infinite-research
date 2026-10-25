#!/usr/bin/env python3
"""Analyze one complete, predeclared R06 active-runtime benchmark receipt.

The reader is intentionally limited to the R06 F210 cohort.  It checks the
immutable plan/result inputs, active-save and marker-pilot custody, then
reports the predeclared median limits and the descriptive 128-minus-1 values.
It neither prepares inputs nor launches Factorio, and it makes no release,
universal-performance, equivalence, or bootstrap claim.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import sys
from typing import Any


KIND = "MIR5RuntimeBenchmarkActiveR06AnalysisV1"
PLAN_KIND = "MIR5PredeclaredActiveRuntimeBenchmarkPlanV1"
RESULT_KIND = "MIR5RuntimeBenchmarkActiveObservedResultV1"
SAMPLE_KIND = "MIR5RuntimeBenchmarkSampleV1"
CAPTURE_KIND = "MIR5RuntimeBenchmarkActiveSeedCaptureV1"
PILOT_KIND = "MIR5RuntimeBenchmarkActiveMarkerPilotV1"
PLAN_PATH = "spec/evidence/runtime-benchmark-active-plan-r06.json"
PLAN_REVISION = "7dcd6d6df9e02f66e5eb00965a36d08daf54a856"
PLAN_SOURCE = "8c078dbad90e0236c9e9fa777f6d776e03b48401"
PLAN_TREE = "0dd2670887647b1794b29a25773147f86f564662"
SOURCE = "b2cf4c2dac43727e2e93cb90b861d2301f7778cd"
SOURCE_TREE = "25442a5bd7838f124952507854426e3b8e868475"
ENGINE_SHA256 = "FE4A1DA30F322A0D0B8AEB3DF7276332222BAAA143E2352569B723E84B2B9060"
PUBLISHED_SHA256 = "A4BB8F47232C689B267EF434F557187A8795C47280FA464169DE917FB579517F"
CANDIDATE_SHA256 = "4F5BEE023930666FC0F921136A69B59861741BE44C311E03D46347D42018ECBC"
INVENTORY_SHA256 = "4FD1A20E6C2E3D3F27D6158D60C931333B0E5053926019BD6C59493A9AF88498"
INVENTORY_CONTENT_SHA256 = "D84635E67886182989AA958024CAF619F0E832CC47A3BF0533BA047C42F0E7D5"
ACTIVE_SEED_CAPTURE_SHA256 = "883DF556BEB4D845929CD9FDAEA867FD01DAB72952CD70A849C17310249C28DB"
MARKER_PILOT_SHA256 = "89329DE94C32E1C9A5C0EDE13AE112C008172FFBB7E13928C203BA1974E50A47"
MAX_PLAN_BYTES = 1024 * 1024
# R06 permits a bounded 8 MiB serialized memory receipt per one of 68 samples.
# The result normally stores far less, but this bound does not reject the
# declared worst-case inline observation representation.
MAX_RESULT_BYTES = 68 * 8 * 1024 * 1024 + 1024 * 1024
MAX_PREPARED_INPUTS_BYTES = 2 * 1024 * 1024
SHA256 = re.compile(r"^[A-F0-9]{64}$")
METRICS = (
    "engine_reported_average_milliseconds_per_tick",
    "operating_system_peak_working_set_bytes",
    "maximum_sampled_working_set_bytes",
    "maximum_sampled_private_bytes",
)


class RuntimeBenchmarkAnalysisError(ValueError):
    """The supplied R06 inputs are not admissible for analysis."""


def _reject_duplicate_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise RuntimeBenchmarkAnalysisError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def _reject_nonfinite_constant(value: str) -> None:
    raise RuntimeBenchmarkAnalysisError(f"non-finite JSON constant: {value}")


def _read_bounded(path: Path, maximum: int, label: str) -> bytes:
    try:
        with path.open("rb") as stream:
            payload = stream.read(maximum + 1)
    except OSError as error:
        raise RuntimeBenchmarkAnalysisError(f"{label} is unreadable: {path}") from error
    if len(payload) > maximum:
        raise RuntimeBenchmarkAnalysisError(f"{label} exceeds {maximum} bytes: {path}")
    return payload


def _read_json(path: Path, maximum: int, label: str) -> tuple[dict[str, Any], str]:
    payload = _read_bounded(path, maximum, label)
    try:
        value = json.loads(
            payload.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_object,
            parse_constant=_reject_nonfinite_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError(f"{label} is not strict UTF-8 JSON: {path}") from error
    if not isinstance(value, dict):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be an object")
    return value, hashlib.sha256(payload).hexdigest().upper()


def _same_json(actual: Any, expected: Any, label: str) -> None:
    if json.dumps(actual, sort_keys=True, separators=(",", ":"), allow_nan=False) != json.dumps(expected, sort_keys=True, separators=(",", ":"), allow_nan=False):
        raise RuntimeBenchmarkAnalysisError(label + " differs from the raw result")


def _validate_prepared_inputs_sidecar(result_path: Path, result: dict[str, Any]) -> None:
    leaf = _string(result.get("prepared_inputs_path"), "prepared inputs path")
    _same(leaf, "runtime-benchmark-active-prepared.json", "prepared inputs path")
    result_parent = result_path.resolve().parent
    sidecar_path = (result_parent / leaf).resolve()
    if sidecar_path.parent != result_parent:
        raise RuntimeBenchmarkAnalysisError("prepared inputs path escapes the raw result directory")
    sidecar, sidecar_sha256 = _read_json(sidecar_path, MAX_PREPARED_INPUTS_BYTES, "prepared inputs sidecar")
    _expect_hash(sidecar_sha256, result.get("prepared_inputs_sha256"), "prepared inputs sidecar SHA-256")
    _same(_integer(sidecar.get("schema"), "prepared inputs sidecar schema"), 1, "prepared inputs sidecar schema")
    _same(_string(sidecar.get("kind"), "prepared inputs sidecar kind"), "MIR5ActiveRuntimeBenchmarkPreparedInputsV1", "prepared inputs sidecar kind")
    _same(_string(sidecar.get("status"), "prepared inputs sidecar status"), "validated-accepted-active-inputs-no-new-native", "prepared inputs sidecar status")
    _same(_integer(sidecar.get("native_launches"), "prepared inputs sidecar native launches"), 0, "prepared inputs sidecar native launches")
    _same(_boolean(sidecar.get("performance_qualification"), "prepared inputs sidecar performance flag"), False, "prepared inputs sidecar performance flag")
    _same(_boolean(sidecar.get("release_qualification"), "prepared inputs sidecar release flag"), False, "prepared inputs sidecar release flag")
    for key in ("plan", "private_controller", "raw_helper_source", "active_seed_capture", "unscored_marker_pilot", "schedule"):
        _same_json(sidecar.get(key), result.get(key), "prepared inputs sidecar " + key)


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be an object")
    return value


def _array(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be an array")
    return value


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise RuntimeBenchmarkAnalysisError(f"{label} must be a non-empty string")
    return value


def _boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be a Boolean")
    return value


def _integer(value: Any, label: str, *, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be an integer")
    if minimum is not None and value < minimum:
        raise RuntimeBenchmarkAnalysisError(f"{label} must be at least {minimum}")
    return value


def _number(value: Any, label: str, *, minimum: float | None = None) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be numeric")
    numeric = float(value)
    if not math.isfinite(numeric):
        raise RuntimeBenchmarkAnalysisError(f"{label} must be finite")
    if minimum is not None and numeric < minimum:
        raise RuntimeBenchmarkAnalysisError(f"{label} must be at least {minimum}")
    return numeric


def _sha256(value: Any, label: str) -> str:
    text = _string(value, label)
    if SHA256.fullmatch(text) is None:
        raise RuntimeBenchmarkAnalysisError(f"{label} must be an uppercase SHA-256")
    return text


def _same(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise RuntimeBenchmarkAnalysisError(f"{label} differs from the fixed R06 contract")


def _expect_hash(actual: Any, expected: Any, label: str) -> str:
    actual_hash = _sha256(actual, label)
    expected_hash = _sha256(expected, f"expected {label}")
    if actual_hash != expected_hash:
        raise RuntimeBenchmarkAnalysisError(f"{label} differs")
    return actual_hash


def _profiles(plan: dict[str, Any]) -> dict[tuple[str, int, str], dict[str, str]]:
    contract = _mapping(plan.get("active_fixture_contract"), "active fixture contract")
    repair = _mapping(contract.get("repair"), "repair fixture contract")
    agriculture = _mapping(contract.get("agriculture"), "agriculture fixture contract")
    answer: dict[tuple[str, int, str], dict[str, str]] = {}
    repair_profiles = _array(repair.get("profiles"), "repair profiles")
    if len(repair_profiles) != 2:
        raise RuntimeBenchmarkAnalysisError("repair profile count differs")
    for entry in repair_profiles:
        row = _mapping(entry, "repair profile")
        path = _string(row.get("path"), "repair profile path")
        arm = "published" if "published" in path else "candidate" if "mir5" in path else ""
        if not arm or ("published" in path and "mir5" in path):
            raise RuntimeBenchmarkAnalysisError("repair profile arm differs")
        key = ("repair-active", 0, arm)
        if key in answer:
            raise RuntimeBenchmarkAnalysisError("repair profile arm duplicates")
        answer[key] = {"path": path, "sha256": _sha256(row.get("sha256"), "repair profile SHA-256")}
    agriculture_profiles = _array(agriculture.get("profiles"), "agriculture profiles")
    if len(agriculture_profiles) != 6:
        raise RuntimeBenchmarkAnalysisError("agriculture profile count differs")
    expression = re.compile(r"agriculture-active-matched-(published|candidate-defaults)-(1|32|128)-f210-2123\.json$")
    for entry in agriculture_profiles:
        row = _mapping(entry, "agriculture profile")
        path = _string(row.get("path"), "agriculture profile path")
        match = expression.search(path)
        if match is None:
            raise RuntimeBenchmarkAnalysisError("agriculture profile identity differs")
        key = ("agriculture-active", int(match.group(2)), match.group(1))
        if key in answer:
            raise RuntimeBenchmarkAnalysisError("agriculture profile arm duplicates")
        answer[key] = {"path": path, "sha256": _sha256(row.get("sha256"), "agriculture profile SHA-256")}
    expected = {
        ("repair-active", 0, "published"),
        ("repair-active", 0, "candidate"),
        *( ("agriculture-active", tier, arm) for tier in (1, 32, 128) for arm in ("published", "candidate-defaults") ),
    }
    if set(answer) != expected:
        raise RuntimeBenchmarkAnalysisError("active profile closure differs")
    return answer


def _staged_profile_path(value: Any, expected_relative: str, label: str) -> None:
    """Require a staged Windows profile locator ending in the fixed repo path."""
    actual = _string(value, label).replace("\\", "/")
    expected = expected_relative.replace("\\", "/")
    if re.fullmatch(r"[A-Za-z]:/.*", actual) is None or not actual.endswith("/" + expected):
        raise RuntimeBenchmarkAnalysisError(label + " differs from the staged fixed profile")


def _validate_plan(plan: dict[str, Any]) -> dict[str, Any]:
    _same(_integer(plan.get("schema"), "plan schema"), 1, "plan schema")
    _same(_string(plan.get("kind"), "plan kind"), PLAN_KIND, "plan kind")
    _same(
        _string(plan.get("status"), "plan status"),
        "predeclared-active-save-capture-required-not-a-result",
        "plan status",
    )
    source = _mapping(plan.get("plan_source"), "plan source")
    _same(_string(source.get("commit"), "plan source commit"), PLAN_SOURCE, "plan source commit")
    _same(_string(source.get("tree"), "plan source tree"), PLAN_TREE, "plan source tree")
    candidate = _mapping(plan.get("candidate"), "candidate")
    _same(_string(candidate.get("source_commit"), "candidate source"), SOURCE, "candidate source")
    _same(_string(candidate.get("source_tree"), "candidate tree"), SOURCE_TREE, "candidate tree")
    _same(_string(candidate.get("asset_root"), "candidate asset root"), "D:/Projects/Factorio/mir5-current-assets-b2cf4c2d-r01", "candidate asset root")
    _expect_hash(candidate.get("asset_inventory_file_sha256"), INVENTORY_SHA256, "candidate inventory SHA-256")
    _expect_hash(candidate.get("asset_inventory_content_sha256"), INVENTORY_CONTENT_SHA256, "candidate inventory content SHA-256")
    candidate_archive = _mapping(candidate.get("f210_archive"), "candidate F210 archive")
    _same(_string(candidate_archive.get("name"), "candidate archive name"), "more-infinite-research_5.0.21000.zip", "candidate archive name")
    _same(_integer(candidate_archive.get("bytes"), "candidate archive bytes", minimum=1), 553767, "candidate archive bytes")
    _expect_hash(candidate_archive.get("sha256"), CANDIDATE_SHA256, "candidate archive SHA-256")
    published = _mapping(plan.get("published"), "published")
    published_archive = _mapping(published.get("f210_archive"), "published F210 archive")
    _same(_string(published_archive.get("name"), "published archive name"), "more-infinite-research_4.7.21002.zip", "published archive name")
    _expect_hash(published_archive.get("sha256"), PUBLISHED_SHA256, "published archive SHA-256")
    engine = _mapping(plan.get("engine"), "engine")
    _same(_string(engine.get("version"), "engine version"), "2.1.23", "engine version")
    _expect_hash(engine.get("sha256"), ENGINE_SHA256, "engine SHA-256")
    harness = _mapping(plan.get("public_harness"), "public harness")
    _same(_string(harness.get("source_reference"), "harness source"), PLAN_SOURCE, "harness source")
    helpers = _array(harness.get("git_blob_sha256"), "raw helper closure")
    if len(helpers) != 12:
        raise RuntimeBenchmarkAnalysisError("raw helper closure count differs")
    seen_helpers: set[str] = set()
    for entry in helpers:
        row = _mapping(entry, "raw helper")
        path = _string(row.get("path"), "raw helper path")
        if path in seen_helpers:
            raise RuntimeBenchmarkAnalysisError("raw helper path duplicates")
        seen_helpers.add(path)
        _sha256(row.get("sha256"), "raw helper SHA-256")
    schedule = _mapping(plan.get("schedule"), "schedule")
    repair = _mapping(schedule.get("repair_active"), "repair schedule")
    agriculture = _mapping(schedule.get("agriculture_active"), "agriculture schedule")
    _same(_integer(repair.get("warmups_per_arm"), "repair warmups"), 2, "repair warmups")
    _same(_integer(repair.get("scored_pairs"), "repair scored pairs"), 8, "repair scored pairs")
    _same(_array(repair.get("arms"), "repair arms"), ["published", "candidate"], "repair arms")
    _same(_integer(agriculture.get("warmups_per_arm_per_tier"), "agriculture warmups"), 2, "agriculture warmups")
    _same(_integer(agriculture.get("scored_pairs_per_tier"), "agriculture scored pairs"), 6, "agriculture scored pairs")
    _same(_array(agriculture.get("tiers"), "agriculture tiers"), [1, 32, 128], "agriculture tiers")
    _same(_array(agriculture.get("arms"), "agriculture arms"), ["published", "candidate-defaults"], "agriculture arms")
    _same(_integer(schedule.get("total_launches"), "total launches"), 68, "total launches")
    command = _mapping(plan.get("benchmark_command"), "benchmark command")
    _same(
        _array(command.get("arguments"), "benchmark command arguments"),
        ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"],
        "benchmark command arguments",
    )
    memory = _mapping(plan.get("process_memory_observation"), "memory observation")
    _same(_string(memory.get("context"), "memory context"), "benchmark", "memory context")
    slot = _mapping(memory.get("expected_slot"), "memory expected slot")
    _same(_string(slot.get("phase"), "memory phase"), "benchmark", "memory phase")
    _same(_string(slot.get("role"), "memory role"), "factorio", "memory role")
    _same(_integer(memory.get("target_interval_milliseconds"), "memory interval"), 250, "memory interval")
    _same(_integer(memory.get("maximum_duration_seconds"), "memory duration"), 900, "memory duration")
    _same(_integer(memory.get("maximum_observations"), "memory observations"), 12000, "memory observations")
    _same(_integer(memory.get("maximum_serialized_bytes"), "memory serialized bytes"), 8 * 1024 * 1024, "memory serialized bytes")
    rules = _mapping(plan.get("comparison_rules"), "comparison rules")
    time_rule = _mapping(rules.get("candidate_time_per_tick_limit"), "time rule")
    _same(_number(time_rule.get("relative_fraction"), "time relative fraction"), 0.1, "time relative fraction")
    _same(_number(time_rule.get("absolute_milliseconds_per_tick"), "time absolute allowance"), 0.25, "time absolute allowance")
    memory_rule = _mapping(rules.get("candidate_memory_limits"), "memory rule")
    _same(_number(memory_rule.get("relative_fraction"), "memory relative fraction"), 0.1, "memory relative fraction")
    _same(_integer(memory_rule.get("absolute_bytes"), "memory absolute allowance"), 64 * 1024 * 1024, "memory absolute allowance")
    _same(_array(memory_rule.get("metrics"), "memory metrics"), list(METRICS[1:]), "memory metrics")
    increment_rule = _mapping(rules.get("agriculture_within_arm_increment_128_minus_1"), "agriculture increment rule")
    _same(_array(increment_rule.get("metrics"), "agriculture increment metrics"), list(METRICS), "agriculture increment metrics")
    _same(
        _string(increment_rule.get("rule"), "agriculture increment rule text"),
        "Report candidate and published 128-minus-1 raw differences separately. A percentage comparison is permitted only when the matching published incremental denominator is finite and strictly positive; otherwise report raw differences only, with no percentage or inferred non-regression conclusion from noise.",
        "agriculture increment rule text",
    )
    resources = _mapping(plan.get("resources"), "resource limits")
    _same(_integer(resources.get("expected_peak_memory_mib_per_factorio"), "resource peak memory"), 4096, "resource peak memory")
    _same(_integer(resources.get("maximum_new_output_mib_per_launch"), "resource output limit"), 120, "resource output limit")
    for key in ("exclusive_native_lock", "direct_existing_archive_library_only", "no_dependency_copy_hardlink_or_extraction"):
        _same(_boolean(resources.get(key), "resource " + key), True, "resource " + key)
    fixture = _mapping(plan.get("active_fixture_contract"), "active fixture contract")
    for name, expected_profiles in (("repair", 2), ("agriculture", 6)):
        row = _mapping(fixture.get(name), f"{name} fixture")
        _same(_array(row.get("required_markers"), f"{name} markers"), ["prepared", "start", "complete"], f"{name} markers")
        if len(_array(row.get("profiles"), f"{name} profiles")) != expected_profiles:
            raise RuntimeBenchmarkAnalysisError(f"{name} profile count differs")
    capture = _mapping(plan.get("active_seed_capture"), "active seed capture")
    _same(_integer(_mapping(capture.get("repair"), "repair capture").get("count"), "repair capture count"), 2, "repair capture count")
    _same(_integer(_mapping(capture.get("agriculture"), "agriculture capture").get("count"), "agriculture capture count"), 6, "agriculture capture count")
    _same(_string(capture.get("closed_save_name"), "active save name"), "mir5-native-active.zip", "active save name")
    _same(_boolean(capture.get("preparation_outside_timed_benchmark"), "capture preparation boundary"), True, "capture preparation boundary")
    pilot = _mapping(plan.get("unscored_marker_pilot"), "marker pilot")
    _same(_integer(pilot.get("count"), "marker pilot count"), 8, "marker pilot count")
    _same(_integer(pilot.get("ticks"), "marker pilot ticks"), 25000, "marker pilot ticks")
    _same(_boolean(pilot.get("not_in_schedule_total"), "marker pilot schedule boundary"), True, "marker pilot schedule boundary")
    _same(_boolean(pilot.get("not_a_timing_or_acceptance_result"), "marker pilot acceptance boundary"), True, "marker pilot acceptance boundary")
    _same(_boolean(plan.get("performance_acceptance"), "plan performance flag"), False, "plan performance flag")
    _same(_boolean(plan.get("release_qualification"), "plan release flag"), False, "plan release flag")
    return {"profiles": _profiles(plan), "helpers": helpers}


def _schedule_template() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    ordinal = 1

    def append(identifier: str, phase: str, scenario: str, tier: int, arm: str, block: int | None) -> None:
        nonlocal ordinal
        rows.append({"ordinal": ordinal, "id": identifier, "phase": phase, "scenario": scenario, "tier": tier, "arm": arm, "block": block})
        ordinal += 1

    for arm in ("published", "candidate"):
        for number in range(1, 3):
            append(f"repair-warmup-{arm}-{number}", "warmup", "repair-active", 0, arm, None)
    for block in range(1, 9):
        arms = ("published", "candidate") if block % 2 else ("candidate", "published")
        for position, arm in enumerate(arms, start=1):
            append(f"repair-b{block}-{position}-{arm}", "scored", "repair-active", 0, arm, block)
    for tier in (1, 32, 128):
        for arm in ("published", "candidate-defaults"):
            for number in range(1, 3):
                append(f"agriculture-{tier}-warmup-{arm}-{number}", "warmup", "agriculture-active", tier, arm, None)
        for block in range(1, 7):
            arms = ("published", "candidate-defaults") if block % 2 else ("candidate-defaults", "published")
            for position, arm in enumerate(arms, start=1):
                append(f"agriculture-{tier}-b{block}-{position}-{arm}", "scored", "agriculture-active", tier, arm, block)
    if len(rows) != 68:
        raise AssertionError("fixed R06 schedule does not contain 68 rows")
    return rows


def _validate_schedule(value: Any) -> list[dict[str, Any]]:
    rows = _array(value, "result schedule")
    expected = _schedule_template()
    if len(rows) != len(expected):
        raise RuntimeBenchmarkAnalysisError("result schedule must contain exactly 68 rows")
    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []
    for source, contract in zip(rows, expected, strict=True):
        row = _mapping(source, "result schedule row")
        identifier = _string(row.get("id"), "schedule id")
        if identifier in seen:
            raise RuntimeBenchmarkAnalysisError("result schedule id duplicates")
        seen.add(identifier)
        _same(identifier, contract["id"], "schedule id")
        actual = {
            "ordinal": _integer(row.get("ordinal"), "schedule ordinal", minimum=1),
            "phase": _string(row.get("phase"), "schedule phase"),
            "scenario": _string(row.get("scenario"), "schedule scenario"),
            "tier": _integer(row.get("tier"), "schedule tier", minimum=0),
            "arm": _string(row.get("arm"), "schedule arm"),
            "block": row.get("block"),
        }
        for key in ("ordinal", "phase", "scenario", "tier", "arm"):
            _same(actual[key], contract[key], f"schedule {key}")
        if contract["block"] is None:
            if actual["block"] is not None:
                raise RuntimeBenchmarkAnalysisError("warmup schedule block must be null")
        else:
            _same(_integer(actual["block"], "schedule block", minimum=1), contract["block"], "schedule block")
        normalized.append({"id": identifier, **actual})
    return normalized


def _marker(value: Any, label: str, kind: str, stage: str, status: str) -> dict[str, Any]:
    marker = _mapping(value, label)
    _same(_string(marker.get("kind"), label + " kind"), kind, label + " kind")
    _same(_string(marker.get("stage"), label + " stage"), stage, label + " stage")
    _same(_string(marker.get("status"), label + " status"), status, label + " status")
    return _mapping(marker.get("witnesses"), label + " witnesses")


def _active_rows() -> list[dict[str, Any]]:
    return [
        {"id": "repair-published", "fixture": "repair", "kind": "repair-stress", "arm": "published", "tier": 0},
        {"id": "repair-candidate", "fixture": "repair", "kind": "repair-stress", "arm": "candidate", "tier": 0},
        *( {"id": f"agriculture-{arm}-{tier}", "fixture": "agriculture", "kind": "agriculture-scale", "arm": arm, "tier": tier}
           for tier in (1, 32, 128) for arm in ("published", "candidate-defaults") ),
    ]


def _validate_prepared_witness(witnesses: dict[str, Any], row: dict[str, Any]) -> None:
    if row["kind"] == "repair-stress":
        _same(_integer(witnesses.get("total_eligible_walls"), "repair prepared total walls"), 1000, "repair prepared total walls")
        _same(_integer(witnesses.get("first_capacity_walls"), "repair prepared capacity"), 256, "repair prepared capacity")
        _same(_integer(witnesses.get("eligible_overflow_walls"), "repair prepared overflow"), 744, "repair prepared overflow")
        _same(_integer(witnesses.get("initial_changed"), "repair prepared changed"), 0, "repair prepared changed")
    else:
        _same(_integer(witnesses.get("real_lab_agriculture_completions"), "agriculture prepared labs"), 2, "agriculture prepared labs")
        planting = _mapping(witnesses.get("native_planting_events"), "agriculture prepared planting events")
        _same(_integer(planting.get("observed"), "agriculture prepared planting"), 0, "agriculture prepared planting")
    _same(_boolean(witnesses.get("pending_physical_work"), "prepared pending physical work"), True, "prepared pending physical work")


def _validate_capture_reference(value: Any, plan_sha256: str, profiles: dict[tuple[str, int, str], dict[str, str]]) -> dict[str, dict[str, Any]]:
    reference = _mapping(value, "active seed capture reference")
    _string(reference.get("path"), "active seed capture path")
    _expect_hash(reference.get("sha256"), ACTIVE_SEED_CAPTURE_SHA256, "active seed capture SHA-256")
    _same(_string(reference.get("kind"), "active seed capture kind"), CAPTURE_KIND, "active seed capture kind")
    _same(_string(reference.get("status"), "active seed capture status"), "prepared-active-saves-not-a-benchmark-result", "active seed capture status")
    record = _mapping(reference.get("record"), "active seed capture record")
    _same(_integer(record.get("schema"), "active seed capture schema"), 1, "active seed capture schema")
    _same(_string(record.get("kind"), "capture record kind"), CAPTURE_KIND, "capture record kind")
    _same(_string(record.get("status"), "capture record status"), "prepared-active-saves-not-a-benchmark-result", "capture record status")
    record_plan = _mapping(record.get("plan"), "capture record plan")
    _expect_hash(record_plan.get("sha256"), plan_sha256, "capture record plan SHA-256")
    _same(_string(record_plan.get("source_revision"), "capture source revision"), PLAN_SOURCE, "capture source revision")
    harness = _mapping(record.get("public_harness"), "capture public harness")
    _same(_string(harness.get("source_reference"), "capture harness source"), PLAN_SOURCE, "capture harness source")
    _same(_boolean(record.get("preparation_outside_timed_benchmark"), "capture preparation boundary"), True, "capture preparation boundary")
    _same(_boolean(record.get("performance_acceptance"), "capture performance flag"), False, "capture performance flag")
    _same(_boolean(record.get("release_qualification"), "capture release flag"), False, "capture release flag")
    captures = _array(record.get("captures"), "active seed captures")
    expected = _active_rows()
    if len(captures) != len(expected):
        raise RuntimeBenchmarkAnalysisError("active seed capture count differs")
    by_id: dict[str, dict[str, Any]] = {}
    for entry in captures:
        row = _mapping(entry, "active seed capture row")
        identifier = _string(row.get("id"), "active seed capture id")
        if identifier in by_id:
            raise RuntimeBenchmarkAnalysisError("active seed capture id duplicates")
        by_id[identifier] = row
    if set(by_id) != {row["id"] for row in expected}:
        raise RuntimeBenchmarkAnalysisError("active seed capture ids differ")
    for expected_row in expected:
        row = by_id[expected_row["id"]]
        for key in ("fixture", "kind", "arm", "tier"):
            _same(row.get(key), expected_row[key], f"active seed capture {key}")
        scenario = "repair-active" if expected_row["kind"] == "repair-stress" else "agriculture-active"
        profile = _mapping(row.get("profile"), "active seed capture profile")
        expected_profile = profiles[(scenario, expected_row["tier"], expected_row["arm"])]
        _staged_profile_path(profile.get("path"), expected_profile["path"], "active seed capture profile path")
        _expect_hash(profile.get("sha256"), expected_profile["sha256"], "active seed capture profile SHA-256")
        seed = _mapping(row.get("active_seed"), "active seed")
        _string(seed.get("path"), "active seed path")
        _sha256(seed.get("sha256"), "active seed SHA-256")
        _integer(seed.get("bytes"), "active seed bytes", minimum=1)
        witnesses = _marker(row.get("prepared_marker"), "prepared marker", expected_row["kind"], "prepared", "pending")
        _validate_prepared_witness(witnesses, expected_row)
        _string(row.get("native_result_path"), "active seed native result path")
        _sha256(row.get("native_result_sha256"), "active seed native result SHA-256")
    return by_id


def _validate_pilot_reference(value: Any, plan_sha256: str, capture_reference: dict[str, Any], captures: dict[str, dict[str, Any]]) -> None:
    reference = _mapping(value, "marker pilot reference")
    _string(reference.get("path"), "marker pilot path")
    _expect_hash(reference.get("sha256"), MARKER_PILOT_SHA256, "marker pilot SHA-256")
    _same(_string(reference.get("kind"), "marker pilot kind"), PILOT_KIND, "marker pilot kind")
    _same(_string(reference.get("status"), "marker pilot status"), "complete-unscored-not-a-performance-result", "marker pilot status")
    record = _mapping(reference.get("record"), "marker pilot record")
    _same(_integer(record.get("schema"), "marker pilot schema"), 1, "marker pilot schema")
    _same(_string(record.get("kind"), "marker pilot record kind"), PILOT_KIND, "marker pilot record kind")
    _same(_string(record.get("status"), "marker pilot record status"), "complete-unscored-not-a-performance-result", "marker pilot record status")
    _expect_hash(record.get("plan_sha256"), plan_sha256, "marker pilot plan SHA-256")
    seed_receipt = _mapping(record.get("active_seed_receipt"), "marker pilot active seed receipt")
    _expect_hash(seed_receipt.get("sha256"), capture_reference.get("sha256"), "marker pilot active seed receipt SHA-256")
    _string(seed_receipt.get("path"), "marker pilot active seed receipt path")
    _same(_integer(record.get("schedule_launches"), "marker pilot schedule launches"), 0, "marker pilot schedule launches")
    _same(_boolean(record.get("performance_acceptance"), "marker pilot performance flag"), False, "marker pilot performance flag")
    _same(_boolean(record.get("release_qualification"), "marker pilot release flag"), False, "marker pilot release flag")
    observations = _array(record.get("observations"), "marker pilot observations")
    if len(observations) != 8:
        raise RuntimeBenchmarkAnalysisError("marker pilot count differs")
    pilots: dict[str, dict[str, Any]] = {}
    for entry in observations:
        row = _mapping(entry, "marker pilot row")
        identifier = _string(row.get("id"), "marker pilot id")
        if identifier in pilots:
            raise RuntimeBenchmarkAnalysisError("marker pilot id duplicates")
        pilots[identifier] = row
    if set(pilots) != set(captures):
        raise RuntimeBenchmarkAnalysisError("marker pilot ids differ")
    for active in _active_rows():
        row = pilots[active["id"]]
        for key in ("kind", "arm", "tier"):
            _same(row.get(key), active[key], f"marker pilot {key}")
        prepared = _marker(row.get("prepared_marker"), "pilot prepared marker", active["kind"], "prepared", "pending")
        _validate_prepared_witness(prepared, active)
        start = _marker(row.get("start_marker"), "pilot start marker", active["kind"], "start", "pending")
        complete = _marker(row.get("complete_marker"), "pilot complete marker", active["kind"], "complete", "passed")
        if active["kind"] == "repair-stress":
            for witnesses, expected_changed, expected_pending in ((start, 0, True), (complete, 256, False)):
                _same(_integer(witnesses.get("total_eligible_walls"), "repair pilot total walls"), 1000, "repair pilot total walls")
                _same(_integer(witnesses.get("first_capacity_walls"), "repair pilot capacity"), 256, "repair pilot capacity")
                _same(_integer(witnesses.get("eligible_overflow_walls"), "repair pilot overflow"), 744, "repair pilot overflow")
                _same(_integer(witnesses.get("initial_changed"), "repair pilot changed"), expected_changed, "repair pilot changed")
                _same(_boolean(witnesses.get("pending_physical_work"), "repair pilot pending work"), expected_pending, "repair pilot pending work")
            _same(_integer(complete.get("reactivation_changed"), "repair pilot reactivation"), 8, "repair pilot reactivation")
        else:
            expected_arm = "published-4.7.21002" if active["arm"] == "published" else "candidate-defaults-mir5"
            for witnesses, observed, pending in ((start, 0, True), (complete, 2 * active["tier"], False)):
                _same(_integer(witnesses.get("tier"), "agriculture pilot tier"), active["tier"], "agriculture pilot tier")
                _same(_string(witnesses.get("arm"), "agriculture pilot arm"), expected_arm, "agriculture pilot arm")
                _same(_integer(witnesses.get("real_lab_agriculture_completions"), "agriculture pilot labs"), 2, "agriculture pilot labs")
                towers = _mapping(witnesses.get("native_towers"), "agriculture pilot towers")
                _same(_integer(towers.get("player"), "agriculture pilot player towers"), active["tier"], "agriculture pilot player towers")
                _same(_integer(towers.get("foreign_zero_research"), "agriculture pilot foreign towers"), active["tier"], "agriculture pilot foreign towers")
                planting = _mapping(witnesses.get("native_planting_events"), "agriculture pilot planting events")
                _same(_integer(planting.get("observed"), "agriculture pilot observed planting"), observed, "agriculture pilot observed planting")
                _same(_integer(planting.get("expected"), "agriculture pilot expected planting"), 2 * active["tier"], "agriculture pilot expected planting")
                _same(_boolean(witnesses.get("pending_physical_work"), "agriculture pilot pending work"), pending, "agriculture pilot pending work")
        _string(row.get("stdout"), "marker pilot stdout path")
        _sha256(row.get("stdout_sha256"), "marker pilot stdout SHA-256")


def _validate_process_memory(value: Any, native: dict[str, Any]) -> None:
    memory = _mapping(value, "process memory receipt")
    _same(_string(memory.get("status"), "process memory status"), "complete-observation", "process memory status")
    _same(_string(memory.get("context"), "process memory context"), "benchmark", "process memory context")
    rows = _array(memory.get("observations"), "process memory observations")
    count = _integer(native.get("sampled_observation_count"), "sampled observation count", minimum=1)
    if len(rows) != count or count > 12000:
        raise RuntimeBenchmarkAnalysisError("process memory observation count differs")
    maximum_working = 0
    maximum_private = 0
    for entry in rows:
        row = _mapping(entry, "process memory row")
        _same(_string(row.get("phase"), "process memory phase"), "benchmark", "process memory phase")
        _same(_string(row.get("role"), "process memory role"), "factorio", "process memory role")
        _integer(row.get("pid"), "process memory PID", minimum=1)
        _string(row.get("start_utc"), "process memory start time")
        working = _integer(row.get("working_set_bytes"), "process memory working bytes", minimum=0)
        private = _integer(row.get("private_bytes"), "process memory private bytes", minimum=0)
        maximum_working = max(maximum_working, working)
        maximum_private = max(maximum_private, private)
    _same(_integer(native.get("maximum_sampled_working_set_bytes"), "sampled working maximum", minimum=0), maximum_working, "sampled working maximum")
    _same(_integer(native.get("maximum_sampled_private_bytes"), "sampled private maximum", minimum=0), maximum_private, "sampled private maximum")


def _validate_physical_markers(value: Any, schedule: dict[str, Any], native: dict[str, Any]) -> None:
    physical = _mapping(value, "physical markers")
    kind = "repair-stress" if schedule["scenario"] == "repair-active" else "agriculture-scale"
    start = _marker(physical.get("start"), "sample start marker", kind, "start", "pending")
    complete = _marker(physical.get("complete"), "sample complete marker", kind, "complete", "passed")
    _string(physical.get("fixture_log"), "sample fixture log path")
    _sha256(physical.get("fixture_log_sha256"), "sample fixture log SHA-256")
    _same(_string(physical.get("stdout"), "sample physical stdout path"), _string(native.get("stdout"), "native stdout path"), "sample physical stdout path")
    _expect_hash(physical.get("stdout_sha256"), native.get("stdout_sha256"), "sample physical stdout SHA-256")
    if kind == "repair-stress":
        for witnesses, expected_changed, expected_pending in ((start, 0, True), (complete, 256, False)):
            _same(_integer(witnesses.get("total_eligible_walls"), "sample repair total walls"), 1000, "sample repair total walls")
            _same(_integer(witnesses.get("first_capacity_walls"), "sample repair capacity"), 256, "sample repair capacity")
            _same(_integer(witnesses.get("eligible_overflow_walls"), "sample repair overflow"), 744, "sample repair overflow")
            _same(_integer(witnesses.get("initial_changed"), "sample repair changed"), expected_changed, "sample repair changed")
            _same(_boolean(witnesses.get("pending_physical_work"), "sample repair pending work"), expected_pending, "sample repair pending work")
        _same(_integer(complete.get("reactivation_changed"), "sample repair reactivation"), 8, "sample repair reactivation")
        return
    expected_arm = "published-4.7.21002" if schedule["arm"] == "published" else "candidate-defaults-mir5"
    for witnesses, observed, pending in ((start, 0, True), (complete, 2 * schedule["tier"], False)):
        _same(_integer(witnesses.get("tier"), "sample agriculture tier"), schedule["tier"], "sample agriculture tier")
        _same(_string(witnesses.get("arm"), "sample agriculture arm"), expected_arm, "sample agriculture arm")
        _same(_integer(witnesses.get("real_lab_agriculture_completions"), "sample agriculture labs"), 2, "sample agriculture labs")
        towers = _mapping(witnesses.get("native_towers"), "sample agriculture towers")
        _same(_integer(towers.get("player"), "sample agriculture player towers"), schedule["tier"], "sample agriculture player towers")
        _same(_integer(towers.get("foreign_zero_research"), "sample agriculture foreign towers"), schedule["tier"], "sample agriculture foreign towers")
        planting = _mapping(witnesses.get("native_planting_events"), "sample agriculture planting events")
        _same(_integer(planting.get("observed"), "sample agriculture observed planting"), observed, "sample agriculture observed planting")
        _same(_integer(planting.get("expected"), "sample agriculture expected planting"), 2 * schedule["tier"], "sample agriculture expected planting")
        _same(_boolean(witnesses.get("pending_physical_work"), "sample agriculture pending work"), pending, "sample agriculture pending work")


def _validate_sample(
    sample: Any,
    schedule: dict[str, Any],
    profiles: dict[tuple[str, int, str], dict[str, str]],
    captures: dict[str, dict[str, Any]],
) -> dict[str, float]:
    row = _mapping(sample, "benchmark observation")
    _same(_string(row.get("kind"), "observation kind"), SAMPLE_KIND, "observation kind")
    _same(_string(row.get("status"), "observation status"), "observed-not-performance-accepted", "observation status")
    _same(_string(row.get("id"), "observation id"), schedule["id"], "observation id")
    _same(_boolean(row.get("scored"), "observation scored"), schedule["phase"] == "scored", "observation scored")
    _same(_string(row.get("scenario"), "observation scenario"), schedule["scenario"], "observation scenario")
    _same(_integer(row.get("tier"), "observation tier", minimum=0), schedule["tier"], "observation tier")
    _same(_string(row.get("arm"), "observation arm"), schedule["arm"], "observation arm")
    engine = _mapping(row.get("engine"), "observation engine")
    _same(_string(engine.get("version"), "observation engine version"), "2.1.23", "observation engine version")
    _expect_hash(engine.get("sha256"), ENGINE_SHA256, "observation engine SHA-256")
    expected_profile = profiles[(schedule["scenario"], schedule["tier"], schedule["arm"])]
    profile = _mapping(row.get("profile"), "observation profile")
    _staged_profile_path(profile.get("path"), expected_profile["path"], "observation profile path")
    _expect_hash(profile.get("sha256"), expected_profile["sha256"], "observation profile SHA-256")
    archives = _mapping(row.get("archives"), "observation archives")
    selected_leaf = "more-infinite-research_4.7.21002.zip" if schedule["arm"] == "published" else "more-infinite-research_5.0.21000.zip"
    selected_hash = PUBLISHED_SHA256 if schedule["arm"] == "published" else CANDIDATE_SHA256
    _expect_hash(archives.get(selected_leaf), selected_hash, "observation player archive SHA-256")
    seed = _mapping(row.get("seed"), "observation seed")
    _string(seed.get("source_path"), "seed source path")
    seed_hash = _sha256(seed.get("source_sha256"), "seed source SHA-256")
    capture_id = "repair-" + schedule["arm"] if schedule["scenario"] == "repair-active" else f"agriculture-{schedule['arm']}-{schedule['tier']}"
    capture_seed = _mapping(captures[capture_id].get("active_seed"), "capture active seed")
    _expect_hash(seed_hash, capture_seed.get("sha256"), "seed source SHA-256")
    _string(seed.get("owned_path"), "owned seed path")
    _same(_string(seed.get("owned_leaf"), "owned seed leaf"), "fresh-owned-active-seed.zip", "owned seed leaf")
    _expect_hash(seed.get("owned_sha256"), seed_hash, "owned seed SHA-256")
    _integer(seed.get("bytes"), "owned seed bytes", minimum=1)
    integrity = _mapping(row.get("seed_integrity_after_sample"), "seed integrity")
    _same(_string(integrity.get("checkpoint"), "seed integrity checkpoint"), "after-sample", "seed integrity checkpoint")
    _same(_string(integrity.get("sample_id"), "seed integrity sample id"), schedule["id"], "seed integrity sample id")
    for key in ("source", "owned"):
        integrity_row = _mapping(integrity.get(key), "seed integrity " + key)
        _expect_hash(integrity_row.get("expected_sha256"), seed_hash, "seed integrity " + key + " expected SHA-256")
        _expect_hash(integrity_row.get("actual_sha256"), seed_hash, "seed integrity " + key + " actual SHA-256")
        _same(_boolean(integrity_row.get("unchanged"), "seed integrity " + key + " unchanged"), True, "seed integrity " + key + " unchanged")
    _same(
        _array(row.get("command"), "observation command"),
        ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"],
        "observation command",
    )
    timing = _mapping(row.get("timing"), "observation timing")
    _same(_integer(timing.get("updates"), "timing updates"), 25000, "timing updates")
    _number(timing.get("total_milliseconds"), "timing total milliseconds", minimum=0.0)
    average = _number(timing.get("average_milliseconds_per_tick"), "timing average milliseconds", minimum=0.0)
    minimum = _number(timing.get("minimum_milliseconds_per_tick"), "timing minimum milliseconds", minimum=0.0)
    maximum = _number(timing.get("maximum_milliseconds_per_tick"), "timing maximum milliseconds", minimum=0.0)
    if minimum > maximum:
        raise RuntimeBenchmarkAnalysisError("timing minimum exceeds maximum")
    native = _mapping(row.get("native_process"), "native process")
    _string(native.get("stdout"), "native stdout path")
    _sha256(native.get("stdout_sha256"), "native stdout SHA-256")
    _string(native.get("resource_ledger"), "native resource ledger path")
    _number(native.get("duration_seconds"), "native duration", minimum=0.0)
    operating_peak = _integer(native.get("root_os_reported_peak_working_set_bytes"), "OS peak working set", minimum=1)
    working = _integer(native.get("maximum_sampled_working_set_bytes"), "sampled working set", minimum=0)
    private = _integer(native.get("maximum_sampled_private_bytes"), "sampled private bytes", minimum=0)
    if operating_peak < working:
        raise RuntimeBenchmarkAnalysisError("OS peak working set is below sampled working set")
    _validate_process_memory(row.get("process_memory"), native)
    _validate_physical_markers(row.get("physical_markers"), schedule, native)
    restoration = _mapping(row.get("library_control_restoration"), "library control restoration")
    _same(_string(restoration.get("status"), "library restoration status"), "restored-direct-library-controls", "library restoration status")
    _expect_hash(restoration.get("profile_sha256"), expected_profile["sha256"], "library restoration profile SHA-256")
    for key in ("dependency_payload_bytes_copied", "archive_links_created", "archive_extractions"):
        _same(_integer(restoration.get(key), "library restoration " + key, minimum=0), 0, "library restoration " + key)
    _array(restoration.get("selected"), "library restoration selected archives")
    _same(_boolean(row.get("performance_acceptance"), "observation performance flag"), False, "observation performance flag")
    _same(_boolean(row.get("release_qualification"), "observation release flag"), False, "observation release flag")
    return {
        "engine_reported_average_milliseconds_per_tick": average,
        "operating_system_peak_working_set_bytes": float(operating_peak),
        "maximum_sampled_working_set_bytes": float(working),
        "maximum_sampled_private_bytes": float(private),
    }


def _summary(values: list[float]) -> dict[str, float | int]:
    if not values:
        raise RuntimeBenchmarkAnalysisError("summary has no values")
    return {
        "n": len(values),
        "median": statistics.median(values),
        "minimum": min(values),
        "maximum": max(values),
    }


def _comparison(published: list[float], candidate: list[float], *, relative: float, absolute: float) -> dict[str, Any]:
    published_summary = _summary(published)
    candidate_summary = _summary(candidate)
    published_median = float(published_summary["median"])
    candidate_median = float(candidate_summary["median"])
    allowance = max(published_median * relative, absolute)
    limit = published_median + allowance
    return {
        "published": published_summary,
        "candidate": candidate_summary,
        "allowance": allowance,
        "limit": limit,
        "candidate_minus_published_median": candidate_median - published_median,
        "status": "within-predeclared-limit" if candidate_median <= limit else "outside-predeclared-limit",
    }


def _increment(one: list[float], one_twenty_eight: list[float], published_increment: float | None = None) -> dict[str, Any]:
    first = _summary(one)
    last = _summary(one_twenty_eight)
    difference = float(last["median"]) - float(first["median"])
    result: dict[str, Any] = {"tier_1": first, "tier_128": last, "raw_128_minus_1": difference}
    if published_increment is not None:
        if math.isfinite(published_increment) and published_increment > 0:
            result["percent_of_published_increment"] = 100.0 * difference / published_increment
            result["percentage_status"] = "reported-positive-finite-published-denominator"
        else:
            result["percent_of_published_increment"] = None
            result["percentage_status"] = "unresolved-nonpositive-or-nonfinite-published-denominator"
    return result


def analyze(plan: dict[str, Any], plan_sha256: str, result: dict[str, Any], result_sha256: str) -> dict[str, Any]:
    contract = _validate_plan(plan)
    _same(_integer(result.get("schema"), "result schema"), 1, "result schema")
    _same(_string(result.get("kind"), "result kind"), RESULT_KIND, "result kind")
    _same(_string(result.get("status"), "result status"), "observed-not-performance-accepted", "result status")
    result_plan = _mapping(result.get("plan"), "result plan")
    _same(_string(result_plan.get("path"), "result plan path"), PLAN_PATH, "result plan path")
    _same(_string(result_plan.get("source_revision"), "result plan revision"), PLAN_REVISION, "result plan revision")
    _expect_hash(result_plan.get("sha256"), plan_sha256, "result plan SHA-256")
    controller = _mapping(result.get("private_controller"), "private controller")
    revision = _string(controller.get("revision"), "private controller revision")
    if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise RuntimeBenchmarkAnalysisError("private controller revision must be a lowercase Git SHA-1")
    _same(_string(controller.get("path"), "private controller path"), "Invoke-RuntimeBenchmark.ps1", "private controller path")
    raw_controller = _sha256(controller.get("raw_git_sha256"), "private controller raw Git SHA-256")
    _expect_hash(controller.get("executed_sha256"), raw_controller, "private controller executed SHA-256")
    _same(_boolean(controller.get("executed_matches_raw_git"), "private controller executed/raw identity"), True, "private controller executed/raw identity")
    helpers = _mapping(result.get("raw_helper_source"), "result raw helper source")
    _same(_string(helpers.get("revision"), "result raw helper revision"), PLAN_SOURCE, "result raw helper revision")
    helper_rows = _array(helpers.get("members"), "result raw helper members")
    if len(helper_rows) != len(contract["helpers"]):
        raise RuntimeBenchmarkAnalysisError("result raw helper closure count differs")
    helper_by_path: dict[str, dict[str, Any]] = {}
    for entry in helper_rows:
        helper = _mapping(entry, "result raw helper member")
        path = _string(helper.get("path"), "result raw helper path")
        if path in helper_by_path:
            raise RuntimeBenchmarkAnalysisError("result raw helper path duplicates")
        helper_by_path[path] = helper
    for declared in contract["helpers"]:
        expected_path = _string(declared.get("path"), "declared helper path")
        if expected_path not in helper_by_path:
            raise RuntimeBenchmarkAnalysisError("result raw helper path is absent")
        actual = helper_by_path[expected_path]
        expected_hash = _sha256(declared.get("sha256"), "declared helper SHA-256")
        _expect_hash(actual.get("raw_git_sha256"), expected_hash, "result raw helper Git SHA-256")
        _expect_hash(actual.get("executed_sha256"), expected_hash, "result raw helper executed SHA-256")
        _integer(actual.get("bytes"), "result raw helper bytes", minimum=1)
    _same(
        _string(result.get("prepared_inputs_path"), "prepared inputs path"),
        "runtime-benchmark-active-prepared.json",
        "prepared inputs path",
    )
    _sha256(result.get("prepared_inputs_sha256"), "prepared inputs SHA-256")
    capture_reference = _mapping(result.get("active_seed_capture"), "active seed capture reference")
    pilot_reference = _mapping(result.get("unscored_marker_pilot"), "marker pilot reference")
    captures = _validate_capture_reference(capture_reference, plan_sha256, contract["profiles"])
    _validate_pilot_reference(pilot_reference, plan_sha256, capture_reference, captures)
    schedule_rows = _validate_schedule(result.get("schedule"))
    observations = _array(result.get("observations"), "benchmark observations")
    if len(observations) != 68:
        raise RuntimeBenchmarkAnalysisError("benchmark observations must contain exactly 68 rows")
    by_id: dict[str, dict[str, Any]] = {}
    for entry in observations:
        row = _mapping(entry, "benchmark observation")
        identifier = _string(row.get("id"), "benchmark observation id")
        if identifier in by_id:
            raise RuntimeBenchmarkAnalysisError("benchmark observation id duplicates")
        by_id[identifier] = row
    if set(by_id) != {row["id"] for row in schedule_rows}:
        raise RuntimeBenchmarkAnalysisError("benchmark observation ids differ from the explicit schedule")
    measurements: dict[tuple[str, int, str], dict[str, list[float]]] = {}
    scored_rows: dict[str, dict[str, float]] = {}
    schedule_output: list[dict[str, Any]] = []
    for schedule in schedule_rows:
        metrics = _validate_sample(by_id[schedule["id"]], schedule, contract["profiles"], captures)
        schedule_output.append(schedule)
        if schedule["phase"] == "scored":
            key = (schedule["scenario"], schedule["tier"], schedule["arm"])
            measurements.setdefault(key, {metric: [] for metric in METRICS})
            for metric, value in metrics.items():
                measurements[key][metric].append(value)
            scored_rows[schedule["id"]] = metrics
    expected_scored = {
        ("repair-active", 0, arm): 8 for arm in ("published", "candidate")
    }
    expected_scored.update({
        ("agriculture-active", tier, arm): 6
        for tier in (1, 32, 128) for arm in ("published", "candidate-defaults")
    })
    if set(measurements) != set(expected_scored):
        raise RuntimeBenchmarkAnalysisError("scored benchmark closure differs")
    for key, count in expected_scored.items():
        for metric in METRICS:
            if len(measurements[key][metric]) != count:
                raise RuntimeBenchmarkAnalysisError("scored benchmark count differs")
    paired: dict[tuple[str, int, int], dict[str, dict[str, float]]] = {}
    for schedule in schedule_rows:
        if schedule["phase"] != "scored":
            continue
        key = (schedule["scenario"], schedule["tier"], schedule["block"])
        paired.setdefault(key, {})[schedule["arm"]] = scored_rows[schedule["id"]]
    pair_output: dict[str, Any] = {"repair_active": [], "agriculture_active": {"tiers": {}}}
    for scenario, tier in [("repair-active", 0), ("agriculture-active", 1), ("agriculture-active", 32), ("agriculture-active", 128)]:
        maximum = 8 if scenario == "repair-active" else 6
        rows: list[dict[str, Any]] = []
        for block in range(1, maximum + 1):
            row = paired.get((scenario, tier, block))
            arms = ("published", "candidate") if scenario == "repair-active" else ("published", "candidate-defaults")
            if row is None or set(row) != set(arms):
                raise RuntimeBenchmarkAnalysisError("scored paired block differs")
            candidate_arm = arms[1]
            rows.append({
                "block": block,
                "candidate_minus_published": {metric: row[candidate_arm][metric] - row["published"][metric] for metric in METRICS},
            })
        if scenario == "repair-active":
            pair_output["repair_active"] = rows
        else:
            pair_output["agriculture_active"]["tiers"][str(tier)] = rows
    comparisons: dict[str, Any] = {"repair_active": {"metrics": {}}, "agriculture_active": {"tiers": {}}}
    all_within = True
    for metric in METRICS:
        relative = 0.1
        absolute = 0.25 if metric == METRICS[0] else float(64 * 1024 * 1024)
        repair = _comparison(
            measurements[("repair-active", 0, "published")][metric],
            measurements[("repair-active", 0, "candidate")][metric],
            relative=relative,
            absolute=absolute,
        )
        comparisons["repair_active"]["metrics"][metric] = repair
        all_within = all_within and repair["status"] == "within-predeclared-limit"
    for tier in (1, 32, 128):
        tier_output: dict[str, Any] = {"metrics": {}}
        for metric in METRICS:
            relative = 0.1
            absolute = 0.25 if metric == METRICS[0] else float(64 * 1024 * 1024)
            current = _comparison(
                measurements[("agriculture-active", tier, "published")][metric],
                measurements[("agriculture-active", tier, "candidate-defaults")][metric],
                relative=relative,
                absolute=absolute,
            )
            tier_output["metrics"][metric] = current
            all_within = all_within and current["status"] == "within-predeclared-limit"
        comparisons["agriculture_active"]["tiers"][str(tier)] = tier_output
    increments: dict[str, Any] = {"published": {}, "candidate_defaults": {}}
    for metric in METRICS:
        published = _increment(
            measurements[("agriculture-active", 1, "published")][metric],
            measurements[("agriculture-active", 128, "published")][metric],
        )
        candidate = _increment(
            measurements[("agriculture-active", 1, "candidate-defaults")][metric],
            measurements[("agriculture-active", 128, "candidate-defaults")][metric],
            float(published["raw_128_minus_1"]),
        )
        increments["published"][metric] = published
        increments["candidate_defaults"][metric] = candidate
    _same(_boolean(result.get("performance_qualification"), "result performance flag"), False, "result performance flag")
    _same(_boolean(result.get("release_qualification"), "result release flag"), False, "result release flag")
    return {
        "schema": 1,
        "kind": KIND,
        "status": "complete-predeclared-r06-analysis",
        "raw_plan": {"path": PLAN_PATH, "revision": PLAN_REVISION, "sha256": plan_sha256, "source_reference": PLAN_SOURCE, "source_tree": PLAN_TREE},
        "raw_result": {"sha256": result_sha256},
        "identity": {
            "candidate_source": SOURCE,
            "candidate_source_tree": SOURCE_TREE,
            "engine": {"version": "2.1.23", "sha256": ENGINE_SHA256},
            "published_archive_sha256": PUBLISHED_SHA256,
            "candidate_archive_sha256": CANDIDATE_SHA256,
            "candidate_inventory_sha256": INVENTORY_SHA256,
        },
        "active_prerequisites": {
            "active_seed_capture": {key: capture_reference[key] for key in ("path", "sha256", "kind", "status")},
            "marker_pilot": {key: pilot_reference[key] for key in ("path", "sha256", "kind", "status")},
        },
        "schedule": schedule_output,
        "paired_block_differences": pair_output,
        "comparisons": comparisons,
        "agriculture_128_minus_1": increments,
        "analysis_verdict": {
            "status": "within-predeclared-limits" if all_within else "outside-predeclared-limits",
            "time_rule": "candidate median <= published median + max(10 percent of published median, 0.25 ms/tick)",
            "memory_rule": "each candidate median <= published median + max(10 percent of published median, 64 MiB)",
        },
        "claims": {
            "native_execution": True,
            "performance_measurement": True,
            "performance_comparison": True,
            "bootstrap": False,
            "equivalence_claim": False,
            "universal_performance_claim": False,
            "release_qualification": False,
        },
        "limitations": [
            "Warmups, active-save capture, and marker pilots are admitted as custody and workload prerequisites, not scored benchmark observations.",
            "The 128-minus-1 section is descriptive; percentage values are omitted unless the matching published increment is finite and strictly positive.",
            "The operating-system root peak and sampled working/private maxima are evaluated separately; sampled values are not instantaneous proven peaks.",
        ],
    }


def _write_output(path: Path, document: dict[str, Any]) -> None:
    if path.exists():
        raise RuntimeBenchmarkAnalysisError(f"refusing to overwrite existing analysis output: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        with path.open("xb") as stream:
            stream.write(payload)
    except OSError as error:
        raise RuntimeBenchmarkAnalysisError(f"unable to write analysis output: {path}") from error


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-plan", required=True, type=Path)
    parser.add_argument("--expected-plan-sha256", required=True)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--expected-result-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(sys.argv[1:] if argv is None else argv)
    try:
        expected_plan_sha256 = _sha256(arguments.expected_plan_sha256, "expected plan SHA-256")
        expected_result_sha256 = _sha256(arguments.expected_result_sha256, "expected result SHA-256")
        plan, plan_sha256 = _read_json(arguments.raw_plan, MAX_PLAN_BYTES, "raw plan")
        result, result_sha256 = _read_json(arguments.result, MAX_RESULT_BYTES, "raw result")
        _expect_hash(plan_sha256, expected_plan_sha256, "raw plan SHA-256")
        _expect_hash(result_sha256, expected_result_sha256, "raw result SHA-256")
        _validate_prepared_inputs_sidecar(arguments.result, result)
        _write_output(arguments.output, analyze(plan, plan_sha256, result, result_sha256))
    except RuntimeBenchmarkAnalysisError as error:
        print(f"[mir5-runtime-benchmark-analysis-refused] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
