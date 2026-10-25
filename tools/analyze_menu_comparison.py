#!/usr/bin/env python3
"""Analyze one frozen R23 responsive-menu observation receipt.

This reader is deliberately narrow.  It accepts only the predeclared R23
schedule and identities, preserves the raw observations, and produces an
endpoint-only menu analysis.  It does not prepare archives, launch Factorio,
or make a release, runtime, UI-fidelity, or memory verdict.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
from typing import Any, Iterable


KIND = "MIR5ResponsiveMenuR23AnalysisV1"
ANALYSIS_PLAN_KIND = "MIR5ResponsiveMenuR23AnalysisPlanV1"
RAW_PLAN_KIND = "MIR5PredeclaredResponsiveMenuExperimentV1"
RESULT_KIND = "MIR5ResponsiveMenuComparisonObservationV1"
OBSERVATION_STATUS = "validated-recorded-menu-interaction-response"
ENDPOINT = "ordinary-responsive-menu"
MAX_ANALYSIS_PLAN_BYTES = 128 * 1024
MAX_RAW_PLAN_BYTES = 512 * 1024
MAX_RESULT_BYTES = 32 * 1024 * 1024
SHA256 = re.compile(r"^[A-F0-9]{64}$")
T95_N8_DF7 = 2.3646242510102993


class MenuAnalysisError(ValueError):
    """A supplied plan or observation is not admissible for R23 analysis."""


def _reject_duplicate_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise MenuAnalysisError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def _reject_nonfinite_constant(value: str) -> None:
    raise MenuAnalysisError(f"non-finite JSON constant: {value}")


def _read_bounded(path: Path, maximum: int, label: str) -> bytes:
    try:
        with path.open("rb") as stream:
            payload = stream.read(maximum + 1)
    except OSError as error:
        raise MenuAnalysisError(f"{label} is unreadable: {path}") from error
    if len(payload) > maximum:
        raise MenuAnalysisError(f"{label} exceeds {maximum} byte limit: {path}")
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
        raise MenuAnalysisError(f"{label} is not strict UTF-8 JSON: {path}") from error
    if not isinstance(value, dict):
        raise MenuAnalysisError(f"{label} must be a JSON object: {path}")
    return value, hashlib.sha256(payload).hexdigest().upper()


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise MenuAnalysisError(f"{label} must be an object")
    return value


def _array(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise MenuAnalysisError(f"{label} must be an array")
    return value


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise MenuAnalysisError(f"{label} must be a non-empty string")
    return value


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise MenuAnalysisError(f"{label} must be an integer")
    return value


def _number(value: Any, label: str, *, positive: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MenuAnalysisError(f"{label} must be a numeric value")
    numeric = float(value)
    if not math.isfinite(numeric):
        raise MenuAnalysisError(f"{label} must be finite")
    if positive and numeric <= 0:
        raise MenuAnalysisError(f"{label} must be positive")
    return numeric


def _boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise MenuAnalysisError(f"{label} must be a boolean")
    return value


def _same(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise MenuAnalysisError(f"{label} does not match the frozen R23 contract")


def _sha256(value: Any, label: str) -> str:
    candidate = _string(value, label).upper()
    if not SHA256.fullmatch(candidate):
        raise MenuAnalysisError(f"{label} must be an uppercase SHA-256 value")
    return candidate


def _expect_hash(actual: Any, expected: Any, label: str) -> None:
    if _sha256(actual, label) != _sha256(expected, f"{label} expected"):
        raise MenuAnalysisError(f"{label} does not match the frozen R23 identity")


def _expected_schedule(schedule: dict[str, Any]) -> list[dict[str, Any]]:
    arms = [_string(value, "analysis schedule arm") for value in _array(schedule.get("arms"), "analysis schedule arms")]
    if arms != ["control-without-mir", "published-4.7", "replay", "candidate-mir5"]:
        raise MenuAnalysisError("analysis schedule arms are not the frozen R23 arms")
    warmups = [_string(value, "analysis warmup arm") for value in _array(schedule.get("warmups"), "analysis warmups")]
    if warmups != arms:
        raise MenuAnalysisError("analysis warmup order is not the frozen R23 order")
    if _string(schedule.get("same_version_aa_arm"), "analysis AA arm") != "published-4.7":
        raise MenuAnalysisError("analysis AA arm is not the frozen R23 arm")
    if _integer(schedule.get("same_version_aa_observations"), "analysis AA observations") != 2:
        raise MenuAnalysisError("analysis AA count is not the frozen R23 count")
    if _integer(schedule.get("counterbalanced_blocks"), "analysis block count") != 8:
        raise MenuAnalysisError("analysis block count is not the frozen R23 count")
    rotations = _array(schedule.get("latin_rotations"), "analysis Latin rotations")
    if len(rotations) != 8:
        raise MenuAnalysisError("analysis Latin rotations must have eight blocks")

    rows: list[dict[str, Any]] = []

    def add(phase: str, arm: str, block: int, position: int) -> None:
        ordinal = len(rows) + 1
        rows.append(
            {
                "ordinal": ordinal,
                "phase": phase,
                "arm": arm,
                "block": block,
                "position": position,
                "label": f"{ordinal:02d}-{phase}-{arm}",
            }
        )

    for position, arm in enumerate(warmups, start=1):
        add("warmup", arm, 0, position)
    for position in (1, 2):
        add("aa-pilot", "published-4.7", 0, position)
    for block, raw_rotation in enumerate(rotations, start=1):
        rotation = [_string(value, f"analysis Latin rotation {block}") for value in _array(raw_rotation, f"analysis Latin rotation {block}")]
        if len(rotation) != 4 or set(rotation) != set(arms):
            raise MenuAnalysisError(f"analysis Latin rotation {block} is not a four-arm permutation")
        for position, arm in enumerate(rotation, start=1):
            add("counterbalanced-comparison", arm, block, position)
    if len(rows) != 38 or _integer(schedule.get("total_rows"), "analysis total rows") != 38:
        raise MenuAnalysisError("analysis schedule must produce exactly 38 rows")
    return rows


def _validate_analysis_plan(plan: dict[str, Any]) -> list[dict[str, Any]]:
    _same(_integer(plan.get("schema"), "analysis plan schema"), 1, "analysis plan schema")
    _same(_string(plan.get("kind"), "analysis plan kind"), ANALYSIS_PLAN_KIND, "analysis plan kind")
    _same(_string(plan.get("status"), "analysis plan status"), "frozen-before-result-inspection", "analysis plan status")
    raw_plan = _mapping(plan.get("raw_plan"), "analysis raw plan")
    _same(_string(raw_plan.get("path"), "analysis raw plan path"), "spec/evidence/bob-angel-menu-plan-r23.json", "analysis raw plan path")
    _same(_integer(raw_plan.get("schema"), "analysis raw plan schema"), 1, "analysis raw plan schema")
    _same(_string(raw_plan.get("kind"), "analysis raw plan kind"), RAW_PLAN_KIND, "analysis raw plan kind")
    _sha256(raw_plan.get("sha256"), "analysis raw plan SHA-256")
    result_contract = _mapping(plan.get("result_contract"), "analysis result contract")
    _same(_integer(result_contract.get("schema"), "result contract schema"), 1, "result contract schema")
    _same(_string(result_contract.get("kind"), "result contract kind"), RESULT_KIND, "result contract kind")
    _same(_string(result_contract.get("status"), "result contract status"), "completed-observation-only", "result contract status")
    _same(_string(result_contract.get("endpoint_class"), "result contract endpoint"), ENDPOINT, "result contract endpoint")
    _same(_string(result_contract.get("required_observation_status"), "result contract observation status"), OBSERVATION_STATUS, "result contract observation status")
    if result_contract.get("result_sha256_required_at_invocation") is not True:
        raise MenuAnalysisError("analysis result hash must be required at invocation")
    if result_contract.get("library_controls_restored") is not True:
        raise MenuAnalysisError("analysis must require restored library controls")
    identity = _mapping(plan.get("identity"), "analysis identity")
    _sha256(_mapping(identity.get("engine"), "analysis engine").get("sha256"), "analysis engine SHA-256")
    _sha256(_mapping(identity.get("profile"), "analysis profile").get("sha256"), "analysis profile SHA-256")
    _sha256(_mapping(identity.get("published"), "analysis published").get("sha256"), "analysis published SHA-256")
    candidate = _mapping(identity.get("candidate"), "analysis candidate")
    _sha256(candidate.get("sha256"), "analysis candidate SHA-256")
    if _integer(candidate.get("bytes"), "analysis candidate bytes") <= 0:
        raise MenuAnalysisError("analysis candidate bytes must be positive")
    _sha256(candidate.get("asset_inventory_sha256"), "analysis inventory SHA-256")
    _sha256(identity.get("ordinary_config_sha256"), "analysis ordinary configuration SHA-256")
    _sha256(identity.get("player_data_sha256"), "analysis player data SHA-256")
    tolerance = _mapping(plan.get("tolerance_policy"), "analysis tolerance policy")
    _same(_number(tolerance.get("aa_absolute_seconds"), "analysis AA absolute seconds", positive=True), 0.5, "analysis AA absolute seconds")
    _same(_number(tolerance.get("aa_relative_percent"), "analysis AA relative percent", positive=True), 5.0, "analysis AA relative percent")
    _same(_number(tolerance.get("control_regression_seconds"), "analysis control drift seconds", positive=True), 0.5, "analysis control drift seconds")
    _same(_number(tolerance.get("minimum_mir_added_time_reduction_percent"), "analysis objective percent", positive=True), 50.0, "analysis objective percent")
    analysis = _mapping(plan.get("analysis"), "analysis settings")
    if _array(analysis.get("scored_blocks"), "analysis scored blocks") != list(range(1, 9)):
        raise MenuAnalysisError("analysis scored blocks are not the frozen R23 blocks")
    if _array(analysis.get("early_control_blocks"), "analysis early control blocks") != [1, 2, 3, 4]:
        raise MenuAnalysisError("analysis early control blocks are not the frozen R23 blocks")
    if _array(analysis.get("late_control_blocks"), "analysis late control blocks") != [5, 6, 7, 8]:
        raise MenuAnalysisError("analysis late control blocks are not the frozen R23 blocks")
    _same(_number(analysis.get("student_t_95_two_sided"), "analysis Student-t critical value", positive=True), T95_N8_DF7, "analysis Student-t critical value")
    _same(_integer(analysis.get("student_t_degrees_of_freedom"), "analysis Student-t degrees of freedom"), 7, "analysis Student-t degrees of freedom")
    return _expected_schedule(_mapping(plan.get("schedule"), "analysis schedule"))


def _validate_raw_plan(raw_plan: dict[str, Any], analysis_plan: dict[str, Any], raw_plan_sha256: str) -> None:
    expected = _mapping(analysis_plan.get("raw_plan"), "analysis raw plan")
    _expect_hash(raw_plan_sha256, expected.get("sha256"), "raw plan SHA-256")
    _same(_integer(raw_plan.get("schema"), "raw plan schema"), 1, "raw plan schema")
    _same(_string(raw_plan.get("kind"), "raw plan kind"), RAW_PLAN_KIND, "raw plan kind")
    identity = _mapping(analysis_plan.get("identity"), "analysis identity")
    engine = _mapping(raw_plan.get("engine"), "raw plan engine")
    expected_engine = _mapping(identity.get("engine"), "analysis engine")
    _same(_string(engine.get("version"), "raw plan engine version"), _string(expected_engine.get("version"), "analysis engine version"), "raw plan engine version")
    _expect_hash(engine.get("sha256"), expected_engine.get("sha256"), "raw plan engine SHA-256")
    _same(_string(raw_plan.get("profile"), "raw plan profile"), _string(_mapping(identity.get("profile"), "analysis profile").get("path"), "analysis profile path"), "raw plan profile")
    _expect_hash(raw_plan.get("profile_checkout_sha256"), _mapping(identity.get("profile"), "analysis profile").get("sha256"), "raw plan profile SHA-256")
    published = _mapping(raw_plan.get("published"), "raw plan published")
    expected_published = _mapping(identity.get("published"), "analysis published")
    _same(_string(published.get("version"), "raw plan published version"), _string(expected_published.get("version"), "analysis published version"), "raw plan published version")
    _expect_hash(published.get("sha256"), expected_published.get("sha256"), "raw plan published SHA-256")
    candidate = _mapping(raw_plan.get("candidate"), "raw plan candidate")
    expected_candidate = _mapping(identity.get("candidate"), "analysis candidate")
    for key in ("source_reference", "source_tree"):
        _same(_string(candidate.get(key), f"raw plan candidate {key}"), _string(identity.get(key), f"analysis {key}"), f"raw plan candidate {key}")
    _expect_hash(candidate.get("sha256"), expected_candidate.get("sha256"), "raw plan candidate SHA-256")
    _same(_integer(candidate.get("bytes"), "raw plan candidate bytes"), _integer(expected_candidate.get("bytes"), "analysis candidate bytes"), "raw plan candidate bytes")
    _expect_hash(candidate.get("asset_inventory_sha256"), expected_candidate.get("asset_inventory_sha256"), "raw plan inventory SHA-256")
    _expect_hash(raw_plan.get("ordinary_config_sha256"), identity.get("ordinary_config_sha256"), "raw plan ordinary configuration SHA-256")
    _expect_hash(raw_plan.get("player_data_sha256"), identity.get("player_data_sha256"), "raw plan player data SHA-256")
    tolerance = _mapping(raw_plan.get("tolerances"), "raw plan tolerances")
    expected_tolerance = _mapping(analysis_plan.get("tolerance_policy"), "analysis tolerance policy")
    _same(_number(tolerance.get("aa_absolute_seconds"), "raw plan AA absolute seconds"), _number(expected_tolerance.get("aa_absolute_seconds"), "analysis AA absolute seconds"), "raw plan AA absolute seconds")
    _same(_number(tolerance.get("aa_relative_percent"), "raw plan AA relative percent"), _number(expected_tolerance.get("aa_relative_percent"), "analysis AA relative percent"), "raw plan AA relative percent")
    _same(_number(tolerance.get("control_regression_seconds"), "raw plan control drift seconds"), _number(expected_tolerance.get("control_regression_seconds"), "analysis control drift seconds"), "raw plan control drift seconds")
    _same(_number(tolerance.get("minimum_mir_added_time_reduction_percent"), "raw plan objective percent"), _number(expected_tolerance.get("minimum_mir_added_time_reduction_percent"), "analysis objective percent"), "raw plan objective percent")


def _validate_identity(result: dict[str, Any], analysis_plan: dict[str, Any]) -> dict[str, Any]:
    identity = _mapping(analysis_plan.get("identity"), "analysis identity")
    inputs = _mapping(result.get("inputs"), "result inputs")
    factorio = _mapping(inputs.get("factorio"), "result Factorio input")
    expected_engine = _mapping(identity.get("engine"), "analysis engine")
    _same(_string(factorio.get("base_version"), "result Factorio version"), _string(expected_engine.get("version"), "analysis engine version"), "result Factorio version")
    _expect_hash(factorio.get("sha256"), expected_engine.get("sha256"), "result Factorio SHA-256")
    profile = _mapping(inputs.get("profile"), "result profile")
    expected_profile = _mapping(identity.get("profile"), "analysis profile")
    _same(_string(profile.get("path"), "result profile path"), _string(expected_profile.get("path"), "analysis profile path"), "result profile path")
    _expect_hash(profile.get("sha256"), expected_profile.get("sha256"), "result profile SHA-256")
    published = _mapping(inputs.get("published"), "result published archive")
    expected_published = _mapping(identity.get("published"), "analysis published archive")
    _same(_string(published.get("version"), "result published version"), _string(expected_published.get("version"), "analysis published version"), "result published version")
    _expect_hash(published.get("sha256"), expected_published.get("sha256"), "result published SHA-256")
    candidate = _mapping(inputs.get("candidate"), "result candidate archive")
    expected_candidate = _mapping(identity.get("candidate"), "analysis candidate")
    _expect_hash(candidate.get("sha256"), expected_candidate.get("sha256"), "result candidate SHA-256")
    _same(_integer(candidate.get("bytes"), "result candidate bytes"), _integer(expected_candidate.get("bytes"), "analysis candidate bytes"), "result candidate bytes")
    replay = _mapping(inputs.get("replay"), "result replay archive")
    _same(_string(replay.get("version"), "result replay version"), _string(expected_published.get("version"), "analysis published version"), "result replay version")
    _expect_hash(replay.get("sha256"), replay.get("sha256"), "result replay SHA-256")
    if _sha256(replay.get("sha256"), "result replay SHA-256") == _sha256(published.get("sha256"), "result published SHA-256"):
        raise MenuAnalysisError("result replay archive must remain byte-distinct from published")
    ordinary = _mapping(inputs.get("ordinary_player_config"), "result ordinary configuration")
    _expect_hash(ordinary.get("sha256"), identity.get("ordinary_config_sha256"), "result ordinary configuration SHA-256")
    player_data = _mapping(inputs.get("player_data"), "result player data")
    _expect_hash(player_data.get("sha256"), identity.get("player_data_sha256"), "result player data SHA-256")
    return {
        "engine": {"version": factorio["base_version"], "sha256": factorio["sha256"]},
        "profile": {"path": profile["path"], "sha256": profile["sha256"]},
        "published": {"version": published["version"], "sha256": published["sha256"]},
        "replay": {"version": replay["version"], "sha256": replay["sha256"]},
        "candidate": {"sha256": candidate["sha256"], "bytes": candidate["bytes"]},
        "ordinary_config_sha256": ordinary["sha256"],
        "player_data_sha256": player_data["sha256"],
    }


def _validate_result(result: dict[str, Any], analysis_plan: dict[str, Any], expected_schedule: list[dict[str, Any]]) -> tuple[dict[int, dict[str, float]], list[float], dict[str, Any]]:
    contract = _mapping(analysis_plan.get("result_contract"), "analysis result contract")
    _same(_integer(result.get("schema"), "result schema"), _integer(contract.get("schema"), "result contract schema"), "result schema")
    _same(_string(result.get("kind"), "result kind"), _string(contract.get("kind"), "result contract kind"), "result kind")
    _same(_string(result.get("status"), "result status"), _string(contract.get("status"), "result contract status"), "result status")
    _same(_string(result.get("endpoint_class"), "result endpoint"), _string(contract.get("endpoint_class"), "result contract endpoint"), "result endpoint")
    if result.get("library_controls_restored") is not True:
        raise MenuAnalysisError("result did not restore library controls")
    claims = _mapping(result.get("claims"), "result claims")
    if claims.get("native_execution") is not True:
        raise MenuAnalysisError("result does not record native execution")
    for field in ("performance_measurement", "performance_comparison", "release_qualification"):
        if claims.get(field) is not False:
            raise MenuAnalysisError(f"raw result unexpectedly claims {field}")
    plan = _mapping(result.get("plan"), "result execution plan")
    if plan.get("fixed_before_execution") is not True:
        raise MenuAnalysisError("result execution plan was not fixed before execution")
    policy = _mapping(plan.get("tolerance_policy"), "result tolerance policy")
    expected_tolerance = _mapping(analysis_plan.get("tolerance_policy"), "analysis tolerance policy")
    policy_checks = {
        "aa_absolute_tolerance_seconds": "aa_absolute_seconds",
        "aa_relative_tolerance_percent": "aa_relative_percent",
        "control_regression_tolerance_seconds": "control_regression_seconds",
        "minimum_mir_added_time_reduction_percent": "minimum_mir_added_time_reduction_percent",
    }
    for actual_key, expected_key in policy_checks.items():
        _same(_number(policy.get(actual_key), f"result tolerance {actual_key}"), _number(expected_tolerance.get(expected_key), f"analysis tolerance {expected_key}"), f"result tolerance {actual_key}")
    plan_rows = _array(plan.get("samples"), "result execution plan samples")
    if len(plan_rows) != len(expected_schedule):
        raise MenuAnalysisError("result execution plan does not contain 38 rows")
    observations = _array(result.get("samples"), "result samples")
    if len(observations) != len(expected_schedule):
        raise MenuAnalysisError("result does not contain exactly 38 samples")
    identity = _validate_identity(result, analysis_plan)
    blocks: dict[int, dict[str, float]] = {}
    aa: list[float] = []
    labels: set[str] = set()
    for index, expected in enumerate(expected_schedule):
        row = _mapping(plan_rows[index], f"result execution plan row {index + 1}")
        sample = _mapping(observations[index], f"result sample {index + 1}")
        observed_plan = _mapping(sample.get("plan"), f"result sample plan {index + 1}")
        for key in ("ordinal", "phase", "arm", "block", "position", "label"):
            actual = observed_plan.get(key)
            if actual != expected[key] or row.get(key) != expected[key]:
                raise MenuAnalysisError(f"result schedule row {index + 1} does not match frozen R23 {key}")
        if expected["label"] in labels:
            raise MenuAnalysisError(f"duplicate result label: {expected['label']}")
        labels.add(expected["label"])
        observation = _mapping(sample.get("observation"), f"result observation {expected['label']}")
        _same(_string(observation.get("status"), f"result observation status {expected['label']}"), OBSERVATION_STATUS, f"result observation status {expected['label']}")
        _same(_string(observation.get("endpoint_class"), f"result observation endpoint {expected['label']}"), ENDPOINT, f"result observation endpoint {expected['label']}")
        elapsed = _number(observation.get("elapsed_seconds"), f"result elapsed seconds {expected['label']}", positive=True)
        _number(observation.get("clock_frequency"), f"result clock frequency {expected['label']}", positive=True)
        if _integer(observation.get("process_id"), f"result process ID {expected['label']}") <= 0:
            raise MenuAnalysisError(f"result process ID {expected['label']} must be positive")
        if expected["phase"] == "aa-pilot":
            aa.append(elapsed)
        elif expected["phase"] == "counterbalanced-comparison":
            block = expected["block"]
            by_arm = blocks.setdefault(block, {})
            if expected["arm"] in by_arm:
                raise MenuAnalysisError(f"duplicate arm in result block {block}: {expected['arm']}")
            by_arm[expected["arm"]] = elapsed
    if len(aa) != 2:
        raise MenuAnalysisError("result does not contain exactly two same-version AA observations")
    expected_arms = {"control-without-mir", "published-4.7", "replay", "candidate-mir5"}
    if set(blocks) != set(range(1, 9)):
        raise MenuAnalysisError("result does not contain exactly eight counterbalanced blocks")
    for block, by_arm in blocks.items():
        if set(by_arm) != expected_arms:
            raise MenuAnalysisError(f"result block {block} does not contain every R23 arm exactly once")
    return blocks, aa, identity


def _summary(values: Iterable[float]) -> dict[str, Any]:
    numbers = list(values)
    if len(numbers) != 8:
        raise MenuAnalysisError("paired R23 summaries require exactly eight values")
    mean = sum(numbers) / len(numbers)
    variance = sum((value - mean) ** 2 for value in numbers) / (len(numbers) - 1)
    standard_deviation = math.sqrt(variance)
    half_width = T95_N8_DF7 * standard_deviation / math.sqrt(len(numbers))
    return {
        "n": len(numbers),
        "arithmetic_mean_seconds": mean,
        "sample_standard_deviation_seconds": standard_deviation,
        "minimum_seconds": min(numbers),
        "maximum_seconds": max(numbers),
        "student_t_95_mean_interval_seconds": {"lower": mean - half_width, "upper": mean + half_width},
    }


def _four_value_summary(values: Iterable[float]) -> dict[str, Any]:
    numbers = list(values)
    if len(numbers) != 4:
        raise MenuAnalysisError("R23 early/late controls require four values per cycle")
    mean = sum(numbers) / len(numbers)
    variance = sum((value - mean) ** 2 for value in numbers) / (len(numbers) - 1)
    return {
        "n": len(numbers),
        "arithmetic_mean_seconds": mean,
        "sample_standard_deviation_seconds": math.sqrt(variance),
        "minimum_seconds": min(numbers),
        "maximum_seconds": max(numbers),
    }


def analyze(analysis_plan: dict[str, Any], raw_plan: dict[str, Any], raw_plan_sha256: str, result: dict[str, Any], result_sha256: str) -> dict[str, Any]:
    expected_schedule = _validate_analysis_plan(analysis_plan)
    _validate_raw_plan(raw_plan, analysis_plan, raw_plan_sha256)
    blocks, aa, identity = _validate_result(result, analysis_plan, expected_schedule)
    tolerance = _mapping(analysis_plan.get("tolerance_policy"), "analysis tolerance policy")
    analysis = _mapping(analysis_plan.get("analysis"), "analysis settings")

    rows: list[dict[str, Any]] = []
    d4_values: list[float] = []
    d5_values: list[float] = []
    direct_values: list[float] = []
    replay_gap_values: list[float] = []
    q_values: list[float] = []
    for block in range(1, 9):
        values = blocks[block]
        control = values["control-without-mir"]
        published = values["published-4.7"]
        replay = values["replay"]
        candidate = values["candidate-mir5"]
        d4 = published - control
        d5 = candidate - control
        direct = candidate - published
        replay_gap = candidate - replay
        q = d5 - 0.5 * d4
        d4_values.append(d4)
        d5_values.append(d5)
        direct_values.append(direct)
        replay_gap_values.append(replay_gap)
        q_values.append(q)
        rows.append(
            {
                "block": block,
                "control_without_mir_seconds": control,
                "published_4_7_seconds": published,
                "replay_seconds": replay,
                "candidate_mir5_seconds": candidate,
                "d4_published_minus_control_seconds": d4,
                "d5_candidate_minus_control_seconds": d5,
                "direct_candidate_minus_published_seconds": direct,
                "candidate_replay_gap_seconds": replay_gap,
                "q_candidate_minus_half_published_increment_seconds": q,
            }
        )
    d4 = _summary(d4_values)
    d5 = _summary(d5_values)
    direct = _summary(direct_values)
    replay_gap = _summary(replay_gap_values)
    q = _summary(q_values)

    aa_difference = abs(aa[0] - aa[1])
    aa_mean = sum(aa) / 2.0
    aa_limit = max(_number(tolerance.get("aa_absolute_seconds"), "analysis AA absolute seconds"), aa_mean * _number(tolerance.get("aa_relative_percent"), "analysis AA relative percent") / 100.0)
    aa_ok = aa_difference <= aa_limit
    early = [blocks[index]["control-without-mir"] for index in range(1, 5)]
    late = [blocks[index]["control-without-mir"] for index in range(5, 9)]
    early_summary = _four_value_summary(early)
    late_summary = _four_value_summary(late)
    control_drift = late_summary["arithmetic_mean_seconds"] - early_summary["arithmetic_mean_seconds"]
    control_ok = control_drift <= _number(tolerance.get("control_regression_seconds"), "analysis control regression seconds")
    denominator_supported = d4["arithmetic_mean_seconds"] > 0 and d4["student_t_95_mean_interval_seconds"]["lower"] > 0
    reduction_percent: float | None
    if denominator_supported:
        reduction_percent = 100.0 * (1.0 - d5["arithmetic_mean_seconds"] / d4["arithmetic_mean_seconds"])
        objective_supported = q["student_t_95_mean_interval_seconds"]["upper"] <= 0.0
        objective_status = "credible-at-least-50-percent" if objective_supported else "point-estimate-not-credible-at-95-percent"
    else:
        reduction_percent = None
        objective_supported = False
        objective_status = "unresolved-nonpositive-or-uncertain-published-increment"

    adverse: list[str] = []
    if not aa_ok:
        adverse.append("same-version-aa-outside-predeclared-tolerance")
    if not control_ok:
        adverse.append("late-control-drift-outside-predeclared-tolerance")
    if not denominator_supported:
        adverse.append("published-added-time-denominator-unresolved")
    if denominator_supported and not objective_supported:
        adverse.append("at-least-50-percent-objective-not-credible-at-95-percent")
    if adverse:
        verdict_status = "analysis-complete-with-adverse-or-unresolved-controls"
    else:
        verdict_status = "analysis-complete-objective-supported"

    return {
        "schema": 1,
        "kind": KIND,
        "status": "analyzed-frozen-r23-raw-observations",
        "analysis_plan": {
            "kind": analysis_plan["kind"],
            "raw_plan_path": analysis_plan["raw_plan"]["path"],
            "raw_plan_sha256": raw_plan_sha256,
            "analysis_plan_identity": {
                "source_reference": analysis_plan["identity"]["source_reference"],
                "source_tree": analysis_plan["identity"]["source_tree"],
                "candidate_asset_inventory_sha256": analysis_plan["identity"]["candidate"]["asset_inventory_sha256"],
            },
        },
        "raw_result": {"sha256": result_sha256},
        "input_identity": identity,
        "same_version_aa": {
            "arm": "published-4.7",
            "observations_seconds": aa,
            "arithmetic_mean_seconds": aa_mean,
            "absolute_difference_seconds": aa_difference,
            "allowed_difference_seconds": aa_limit,
            "status": "within-predeclared-tolerance" if aa_ok else "adverse-outside-predeclared-tolerance",
        },
        "control_drift": {
            "early_blocks": [1, 2, 3, 4],
            "late_blocks": [5, 6, 7, 8],
            "early": early_summary,
            "late": late_summary,
            "late_minus_early_seconds": control_drift,
            "allowed_seconds": tolerance["control_regression_seconds"],
            "status": "within-predeclared-tolerance" if control_ok else "adverse-outside-predeclared-tolerance",
        },
        "paired_blocks": rows,
        "summaries": {
            "published_added_time_d4_seconds": d4,
            "candidate_added_time_d5_seconds": d5,
            "direct_candidate_minus_published_seconds": direct,
            "candidate_replay_gap_seconds": replay_gap,
            "q_candidate_minus_half_published_increment_seconds": q,
        },
        "objective": {
            "minimum_reduction_percent": tolerance["minimum_mir_added_time_reduction_percent"],
            "reduction_percent": reduction_percent,
            "denominator_status": "positive-with-positive-95-percent-lower-bound" if denominator_supported else "unresolved-nonpositive-or-uncertain",
            "q_95_percent_upper_seconds": q["student_t_95_mean_interval_seconds"]["upper"],
            "status": objective_status,
        },
        "menu_verdict": {
            "status": verdict_status,
            "adverse_or_unresolved": adverse,
            "scope": "ordinary responsive-menu endpoint only; not a release, runtime, UI fidelity, or memory verdict",
        },
        "inference": {
            "method": "arithmetic paired-block summaries with two-sided Student-t 95-percent mean intervals",
            "n": 8,
            "degrees_of_freedom": 7,
            "critical_value": analysis["student_t_95_two_sided"],
            "assumption": analysis["assumption"],
            "bootstrap": "not used",
            "replay_gap": "diagnostic only; no threshold is imposed",
        },
        "claims": {
            "native_execution": True,
            "performance_measurement": True,
            "performance_comparison": True,
            "release_qualification": False,
            "runtime_qualification": False,
            "ui_fidelity_qualification": False,
            "memory_qualification": False,
        },
        "limitations": [
            "Raw per-record elapsed values and spread are retained above; this reader does not select, replace, or extend samples.",
            "A/A or late-control failure remains an explicit adverse observation and is not reclassified as a pass.",
            "A percentage is omitted when the published added-time denominator is nonpositive or its Student-t 95-percent lower bound is not positive.",
        ],
    }


def _write_output(path: Path, document: dict[str, Any]) -> None:
    if path.exists():
        raise MenuAnalysisError(f"refusing to overwrite existing analysis output: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    try:
        with path.open("xb") as stream:
            stream.write(encoded)
    except OSError as error:
        raise MenuAnalysisError(f"unable to write analysis output: {path}") from error


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analysis-plan", required=True, type=Path)
    parser.add_argument("--raw-plan", required=True, type=Path)
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--expected-result-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(sys.argv[1:] if argv is None else argv)
    try:
        expected_result_sha256 = _sha256(arguments.expected_result_sha256, "expected result SHA-256")
        analysis_plan, _ = _read_json(arguments.analysis_plan, MAX_ANALYSIS_PLAN_BYTES, "analysis plan")
        raw_plan, raw_plan_sha256 = _read_json(arguments.raw_plan, MAX_RAW_PLAN_BYTES, "raw plan")
        result, result_sha256 = _read_json(arguments.result, MAX_RESULT_BYTES, "raw result")
        _expect_hash(result_sha256, expected_result_sha256, "raw result SHA-256")
        output = analyze(analysis_plan, raw_plan, raw_plan_sha256, result, result_sha256)
        _write_output(arguments.output, output)
    except MenuAnalysisError as error:
        print(f"[mir5-menu-analysis-refused] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
