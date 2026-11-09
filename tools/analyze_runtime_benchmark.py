#!/usr/bin/env python3
"""Analyze one complete, explicitly selected active-runtime benchmark cohort.

The reader admits the frozen R06, current38C, current505-ground and current510 mixed F210 cohorts. It checks the
immutable plan/result inputs, active-save and marker-pilot custody, then
reports the predeclared median limits and the descriptive 128-minus-1 values.
It neither prepares inputs nor launches Factorio, and it makes no release,
universal-performance, equivalence, or bootstrap claim.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
import json
import math
from pathlib import Path, PureWindowsPath
import re
import statistics
import subprocess
import sys
import zipfile
from typing import Any


KIND = "MIR5RuntimeBenchmarkActiveR06AnalysisV1"
PLAN_KIND = "MIR5PredeclaredActiveRuntimeBenchmarkPlanV1"
RESULT_KIND = "MIR5RuntimeBenchmarkActiveObservedResultV1"
SAMPLE_KIND = "MIR5RuntimeBenchmarkSampleV1"
CAPTURE_KIND = "MIR5RuntimeBenchmarkActiveSeedCaptureV1"
PILOT_KIND = "MIR5RuntimeBenchmarkActiveMarkerPilotV1"
PLAN_PATH = "spec/evidence/runtime-benchmark-active-plan-r06.json"
PLAN_SHA256 = "816BA8FE3589967CC456F189F5F3F584289FB553DAFADBB64ACAEF32DD306C4F"
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
ACTIVE_PREREQUISITES_CAPSULE = "spec/evidence/runtime-active-r06-physical-native-receipts.json.gz"
ACTIVE_PREREQUISITES_CAPSULE_SHA256 = "23466064A3C2E376A93FAFD9D5772038186BF4FB5D993E56953F5B145AD5FE88"
ASSET_ROOT = "D:/Projects/Factorio/mir5-current-assets-b2cf4c2d-r01"
CANDIDATE_BYTES = 553767
CANDIDATE_LEAF = "more-infinite-research_5.0.21000.zip"
ANALYSIS_STATUS = "complete-predeclared-r06-analysis"
REPAIR_PROFILE_PREFIX = "tests/profiles/repair-stress-active-"
AGRICULTURE_PROFILE_PREFIX = "tests/profiles/agriculture-active-matched-"
# Select one frozen input tuple per CLI invocation. R06 remains the default,
# including its exact output bytes; neither selection changes the analysis.
_R06_BINDINGS = {name: globals()[name] for name in (
    "KIND", "PLAN_PATH", "PLAN_SHA256", "PLAN_REVISION", "PLAN_SOURCE", "PLAN_TREE",
    "SOURCE", "SOURCE_TREE", "ENGINE_SHA256", "CANDIDATE_SHA256", "INVENTORY_SHA256",
    "INVENTORY_CONTENT_SHA256", "ACTIVE_SEED_CAPTURE_SHA256", "MARKER_PILOT_SHA256",
    "ACTIVE_PREREQUISITES_CAPSULE", "ACTIVE_PREREQUISITES_CAPSULE_SHA256",
    "ASSET_ROOT", "CANDIDATE_BYTES", "CANDIDATE_LEAF", "ANALYSIS_STATUS", "REPAIR_PROFILE_PREFIX", "AGRICULTURE_PROFILE_PREFIX",
)}
_CURRENT38C_BINDINGS = {
    "KIND": "MIR5RuntimeBenchmarkActiveCurrent38CAnalysisV1",
    "PLAN_PATH": "spec/evidence/runtime-current38c-active-plan-r01.json",
    "PLAN_SHA256": "9CA4F3A77784791827C7A70DA353ADAC9E2B9E46A5231341B40F0AB554F003F0",
    "PLAN_REVISION": "5efe123bbae5c5c2168c52a35920aa9e16d3636a",
    "PLAN_SOURCE": "5d6521e953b51207dd51b4d99bbdab8ec954655d",
    "PLAN_TREE": "cb660c1393e6d8364c0e838e9d63ef151604dd95",
    "SOURCE": "b3bbd8d37b37bfee2e258b3e8a2f223dcf3860b3",
    "SOURCE_TREE": "fbb7e9135280ce7f69692e9b0c4a44d743793f45",
    "ENGINE_SHA256": "8DC3979B88784C111D51EC942F04345554635A1B93B7BD7CF536A1E7E903DB38",
    "CANDIDATE_SHA256": "38C84CCBC4BFDA62FCB078772C4690AB81228484744A36D9EA303F5A75B16447",
    "INVENTORY_SHA256": "5EEE95F927897C3743B091F8930B60A96DAE516B36D704870C3CBE10EF66DFBD",
    "INVENTORY_CONTENT_SHA256": "C66E61A535FF0BF333FB647E07B84AD53FA8CD707636BADB6A59C750FBFC8CAA",
    "ACTIVE_SEED_CAPTURE_SHA256": "7CAD16B96FE400E511916C9B96646BBC552E75B9E6CB48D124E1A328A98C484C",
    "MARKER_PILOT_SHA256": "A07F5D5366EE90931EE6E3CF700AE65E4D353C5DC65F93BCAD10DB755E168A6A",
    "ACTIVE_PREREQUISITES_CAPSULE": "spec/evidence/runtime-current38c-physical-native-receipts-r01.json.gz",
    "ACTIVE_PREREQUISITES_CAPSULE_SHA256": "621918B6B2382DF2A382ECD0E289EE1EB060436A265A743E4D409C465CE839F1",
    "ASSET_ROOT": "D:\\Projects\\Factorio\\more-infinite-research\\build\\packages\\fbb7-all17-r01",
    "CANDIDATE_BYTES": 692759,
    "CANDIDATE_LEAF": "more-infinite-research_5.0.21000.zip",
    "ANALYSIS_STATUS": "complete-predeclared-current38c-analysis",
    "REPAIR_PROFILE_PREFIX": "tests/profiles/runtime-current38c-repair-",
    "AGRICULTURE_PROFILE_PREFIX": "tests/profiles/runtime-current38c-agriculture-",
}
_CURRENT505_GROUND_BINDINGS = {
    **_CURRENT38C_BINDINGS,
    "KIND": "MIR505GroundActiveRuntimeAnalysisV1",
    "PLAN_PATH": "spec/evidence/runtime505-active-plan-r02.json",
    "PLAN_SHA256": "5F73A850827290FE760E7C04B3F60C991E3205B08043D046852DB968A267212C",
    "PLAN_REVISION": "848cc35300777ad952b0486135f2460c584e0d4e",
    "PLAN_SOURCE": "23ab190b0037dfb0c9765df94f951300b5a05a16",
    "PLAN_TREE": "f1f989d42add1cb033d103a871dcdee6d9167e20",
    "SOURCE": "0700a3d6cf1a2ac41579e90484eab3a8cad2739d",
    "SOURCE_TREE": "41d36ed8db131404692d5c054da3c87f7b54aecb",
    "CANDIDATE_SHA256": "3537810989FCD72232AF4597B28C699D83AE0E9B77FDAF42AF57A01E29B65E6A",
    "INVENTORY_SHA256": "388F9B1DEF4F2E8EB43D01E5F5A4A976457B43A797D6189E064D4442F23DEB31",
    "INVENTORY_CONTENT_SHA256": "76CC1B995A6A33915A0FAFDA8EC2504B7755ABFA448D61D58C034C4D0DB06D6C",
    "ACTIVE_SEED_CAPTURE_SHA256": "A449FF36E95491F7D3F4ED24217BCCED193F1E5E73D5A123DB581DB86363FFD6",
    "MARKER_PILOT_SHA256": "4AD021E596B64752FBBA16BC3A66BC271BEF3D16DD95D1833976F57B0F4A3DE6",
    "ACTIVE_PREREQUISITES_CAPSULE": "spec/evidence/runtime505-ground-physical-native-receipts-r02.json.gz",
    "ACTIVE_PREREQUISITES_CAPSULE_SHA256": "A049ADFABCD2144BF7DC12AA659CF9D5C930F1B601D689583E970F71752C85DC",
    "ASSET_ROOT": "D:/Projects/Factorio/more-infinite-research/build/packages/candidate505-0700-final-freeze-r01",
    "CANDIDATE_BYTES": 805471,
    "CANDIDATE_LEAF": "more-infinite-research_5.0.21005.zip",
    "ANALYSIS_STATUS": "complete-predeclared-current505-ground-analysis",
    "REPAIR_PROFILE_PREFIX": "tests/profiles/runtime505-repair-",
    "AGRICULTURE_PROFILE_PREFIX": "tests/profiles/runtime505-agriculture-",
}
_CURRENT510_BINDINGS = {
    **_CURRENT505_GROUND_BINDINGS,
    "KIND": "MIR510MixedActiveRuntimeAnalysisV1",
    "PLAN_PATH": "spec/evidence/runtime510-active-plan-r01.json",
    "PLAN_SHA256": "9CDED5FE074894D734210CB432384BF4B509D69AD9CB527424701358EF7054F9",
    "PLAN_REVISION": "8ab529a090128979014ebfe968b794b7511679f0",
    "PLAN_SOURCE": "32feeb99db3cb998f30aa73d11e8f3ebdbd487e6",
    "PLAN_TREE": "1f2ca1f4af0983df7dc990e4a9aaf31e4eb9a955",
    "SOURCE": "8e5ce79be9595c888ed6cad4aa8d2eecd325767d",
    "SOURCE_TREE": "416e7b290caa3ce2c164e5496d482a2041e43e90",
    "CANDIDATE_SHA256": "C625D648978F6FE677B5EDC5C68090A2AA9A939D48A54A736610D55E47337806",
    "INVENTORY_SHA256": "67D1C28B222C825F6B551B88EBC70579C166BADD4A985570D7E9FAB9D509953A",
    "INVENTORY_CONTENT_SHA256": "0D397ECEA4D9E2DF22DDE027E445B281E7813D0A0D2711A02E647BA1E6D83ED0",
    "ACTIVE_PREREQUISITES_CAPSULE": "spec/evidence/runtime510-mixed-physical-native-receipts-r01.json.gz",
    "ACTIVE_PREREQUISITES_CAPSULE_SHA256": "9B204C353DB4FDD6DCE51C0307A25058C1978E46B7E3249548AF21E5246D76F0",
    "ASSET_ROOT": "D:/Projects/Factorio/.task-builds/mir510-freeze-r02",
    "CANDIDATE_BYTES": 996956,
    "CANDIDATE_LEAF": "more-infinite-research_5.0.21010.zip",
    "ANALYSIS_STATUS": "complete-predeclared-current510-mixed-analysis",
    "REPAIR_PROFILE_PREFIX": "tests/profiles/runtime510-repair-",
    "AGRICULTURE_PROFILE_PREFIX": "tests/profiles/runtime510-agriculture-",
}
_CURRENT510_ORIGINS_SHA256 = "1F14705A18EF6D3F218B6235C68DFB3BA2FCF3BA32864F13B2EEE8454DBEA2DE"
_CURRENT510_PILOT_SHA256 = "27B521E148D82C5A3B3EF0050A286310179B5AA2F25473D453A72D04C0305DFC"
_CURRENT510_CONTROLLER_REVISION = "d35f0bb2d23c1517af5025685f05f1527ef3e648"
_CURRENT510_CONTROLLER_SHA256 = "2AF27FC250BEC34D8626A1028C136FA879D0CA85ECE6827D930A32EAB88CF5D1"
_CURRENT505_GROUND_PROFILE_ALIASES = {
    "tests/profiles/runtime-current38c-repair-published-f210-2123.json": "tests/profiles/runtime505-repair-published-f210-2123.json",
    "tests/profiles/runtime505-repair-candidate-f210-2123-r01.json": "tests/profiles/runtime505-repair-candidate-f210-2123.json",
    **{f"tests/profiles/runtime-current38c-agriculture-published-{tier}-f210-2123.json":
       f"tests/profiles/runtime505-agriculture-published-{tier}-f210-2123.json" for tier in (1, 32, 128)},
    **{f"tests/profiles/runtime505-agriculture-candidate-defaults-{tier}-f210-2123-r01.json":
       f"tests/profiles/runtime505-agriculture-candidate-defaults-{tier}-f210-2123.json" for tier in (1, 32, 128)},
}
MAX_PLAN_BYTES = 1024 * 1024
MAX_ACTIVE_PREREQUISITES_CAPSULE_BYTES = 128 * 1024
# R06 permits a bounded 8 MiB serialized memory receipt per one of 68 samples.
# The result normally stores far less, but this bound does not reject the
# declared worst-case inline observation representation.
MAX_RESULT_BYTES = 68 * 8 * 1024 * 1024 + 1024 * 1024
MAX_PREPARED_INPUTS_BYTES = 2 * 1024 * 1024
SHA256 = re.compile(r"^[A-F0-9]{64}$")
PILOT_START_UTC = re.compile(
    r"^(?P<year>[0-9]{4})-(?P<month>[0-9]{2})-(?P<day>[0-9]{2})"
    r"T(?P<hour>[0-9]{2}):(?P<minute>[0-9]{2}):(?P<second>[0-9]{2})"
    r"(?:\.(?P<fraction>[0-9]{1,7}))?Z$"
)
METRICS = (
    "engine_reported_average_milliseconds_per_tick",
    "operating_system_peak_working_set_bytes",
    "maximum_sampled_working_set_bytes",
    "maximum_sampled_private_bytes",
)


class RuntimeBenchmarkAnalysisError(ValueError):
    """The supplied inputs do not match the selected frozen cohort."""


def select_cohort(cohort: str) -> None:
    """Choose an explicit frozen tuple before reading any plan or result."""
    if cohort not in ("r06", "current38c", "current505-ground", "current510-mixed"):
        raise RuntimeBenchmarkAnalysisError("unknown frozen runtime cohort")
    globals().update(_R06_BINDINGS if cohort == "r06" else
                     _CURRENT38C_BINDINGS if cohort == "current38c" else
                     _CURRENT505_GROUND_BINDINGS if cohort == "current505-ground" else _CURRENT510_BINDINGS)


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


def _frozen_active_prerequisites() -> tuple[dict[str, Any], dict[str, Any]]:
    """Read the accepted R06 non-scored prerequisites that bind sample closure."""
    capsule_path = Path(__file__).resolve().parents[1] / ACTIVE_PREREQUISITES_CAPSULE
    payload = _read_bounded(capsule_path, MAX_ACTIVE_PREREQUISITES_CAPSULE_BYTES, "active prerequisite capsule")
    _expect_hash(hashlib.sha256(payload).hexdigest().upper(), ACTIVE_PREREQUISITES_CAPSULE_SHA256, "active prerequisite capsule SHA-256")
    try:
        capsule = json.loads(
            gzip.decompress(payload).decode("utf-8"),
            object_pairs_hook=_reject_duplicate_object,
            parse_constant=_reject_nonfinite_constant,
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("active prerequisite capsule is not strict gzip JSON") from error
    files = _array(_mapping(capsule, "active prerequisite capsule").get("files"), "active prerequisite files")
    expected = {
        "original/active-seed-captures.json": ACTIVE_SEED_CAPTURE_SHA256,
        "original/active-marker-pilots.json": MARKER_PILOT_SHA256,
    }
    records: dict[str, dict[str, Any]] = {}
    for entry in files:
        row = _mapping(entry, "active prerequisite file")
        path = _string(row.get("path"), "active prerequisite path")
        if path not in expected:
            continue
        try:
            decoded = base64.b64decode(_string(row.get("base64"), "active prerequisite base64"), validate=True)
        except ValueError as error:
            raise RuntimeBenchmarkAnalysisError("active prerequisite base64 is invalid") from error
        _same(_integer(row.get("bytes"), "active prerequisite bytes", minimum=1), len(decoded), "active prerequisite bytes")
        _expect_hash(row.get("sha256"), expected[path], "active prerequisite entry SHA-256")
        _expect_hash(hashlib.sha256(decoded).hexdigest().upper(), expected[path], "active prerequisite payload SHA-256")
        try:
            record = json.loads(
                decoded.decode("utf-8"),
                object_pairs_hook=_reject_duplicate_object,
                parse_constant=_reject_nonfinite_constant,
            )
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeBenchmarkAnalysisError("active prerequisite payload is not strict JSON") from error
        records[path] = _mapping(record, "active prerequisite record")
    if set(records) != set(expected):
        raise RuntimeBenchmarkAnalysisError("active prerequisite payload closure differs")
    return records["original/active-seed-captures.json"], records["original/active-marker-pilots.json"]


def _same_json(actual: Any, expected: Any, label: str) -> None:
    if json.dumps(actual, sort_keys=True, separators=(",", ":"), allow_nan=False) != json.dumps(expected, sort_keys=True, separators=(",", ":"), allow_nan=False):
        raise RuntimeBenchmarkAnalysisError(label + " differs from the raw result")


def _canonical_pilot_start_utc(value: Any, label: str) -> str:
    """Preserve the producer's UTC instant while accepting only zero elision."""
    text = _string(value, label)
    match = PILOT_START_UTC.fullmatch(text)
    if match is None:
        raise RuntimeBenchmarkAnalysisError(label + " must be a strict UTC timestamp")
    year, month, day, hour, minute, second = (int(match.group(name)) for name in ("year", "month", "day", "hour", "minute", "second"))
    leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
    month_days = (31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
    if year < 1 or not 1 <= month <= 12 or not 1 <= day <= month_days[month - 1] or hour > 23 or minute > 59 or second > 59:
        raise RuntimeBenchmarkAnalysisError(label + " must be a valid UTC timestamp")
    fraction = (match.group("fraction") or "").ljust(7, "0")
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}.{fraction}Z"


def _normalized_pilot_record(record: Any, label: str) -> dict[str, Any]:
    """Normalize only the DateTime leaves re-emitted by the scheduled producer."""
    normalized = dict(_mapping(record, label))
    observations: list[dict[str, Any]] = []
    for observation_index, observation_value in enumerate(_array(normalized.get("observations"), label + " observations")):
        observation = dict(_mapping(observation_value, label + " observation"))
        native = dict(_mapping(observation.get("native_result"), label + " native result"))
        memory = dict(_mapping(native.get("process_memory"), label + " process memory"))
        rows: list[dict[str, Any]] = []
        for memory_index, memory_value in enumerate(_array(memory.get("observations"), label + " process-memory observations")):
            row = dict(_mapping(memory_value, label + " process-memory observation"))
            row["start_utc"] = _canonical_pilot_start_utc(
                row.get("start_utc"),
                f"{label} observations[{observation_index}].native_result.process_memory.observations[{memory_index}].start_utc",
            )
            rows.append(row)
        memory["observations"] = rows
        native["process_memory"] = memory
        observation["native_result"] = native
        observations.append(observation)
    normalized["observations"] = observations
    return normalized


def _same_pilot_record(actual: Any, expected: Any, label: str) -> None:
    _same_json(_normalized_pilot_record(actual, label), _normalized_pilot_record(expected, label), label)


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
    if KIND == _CURRENT510_BINDINGS["KIND"]:
        for key in ("plan", "private_controller", "raw_helper_source", "mixed_prerequisites", "row_provenance", "schedule"):
            _same_json(sidecar.get(key), result.get(key), "prepared inputs sidecar " + key)
        plan, plan_sha = _read_json(Path(__file__).resolve().parents[1] / PLAN_PATH, MAX_PLAN_BYTES, "current510 plan")
        contract = _validate_plan(plan, plan_sha)
        captures, pilots, _ = _validate_current510_mixed(result, contract["profiles"])
        _validate_current510_provenance(result.get("row_provenance"), captures, contract["profiles"])
        bindings = _mapping(sidecar.get("bindings"), "current510 prepared bindings")
        if set(bindings) != set(captures):
            raise RuntimeBenchmarkAnalysisError("current510 prepared binding ids differ")
        for row in _active_rows():
            binding = _mapping(bindings[row["id"]], "current510 prepared binding")
            scenario = "repair-active" if row["kind"] == "repair-stress" else "agriculture-active"
            expected_profile = contract["profiles"][(scenario, row["tier"], row["arm"])]
            profile = _mapping(binding.get("profile"), "current510 binding profile")
            _staged_profile_path(profile.get("path"), expected_profile["path"], "current510 binding profile")
            _expect_hash(profile.get("sha256"), expected_profile["sha256"], "current510 binding profile")
            if _archive_closure(binding.get("archives"), "current510 binding archives") != _archive_closure(pilots[row["id"]].get("archives"), "current510 prerequisite pilot archives"):
                raise RuntimeBenchmarkAnalysisError("current510 prepared archive closure differs")
            seed = _mapping(binding.get("seed"), "current510 binding seed")
            original = _mapping(captures[row["id"]].get("active_seed"), "current510 original seed")
            _same(_string(seed.get("path"), "current510 binding seed path"), original["path"], "current510 binding seed path")
            _expect_hash(seed.get("sha256"), original["sha256"], "current510 binding seed")
            _same(_integer(seed.get("bytes"), "current510 binding seed bytes"), original["bytes"], "current510 binding seed bytes")
            engine = _mapping(binding.get("engine"), "current510 binding engine")
            _same(_string(engine.get("version"), "current510 binding engine version"), "2.1.23", "current510 binding engine version")
            _expect_hash(engine.get("sha256"), ENGINE_SHA256, "current510 binding engine")
            _same(PureWindowsPath(_string(binding.get("library"), "current510 binding library")), PureWindowsPath("D:/Projects/Factorio/testmods/2.1"), "current510 binding library")
        return
    for key in ("plan", "private_controller", "raw_helper_source", "active_seed_capture", "unscored_marker_pilot", "schedule"):
        _same_json(sidecar.get(key), result.get(key), "prepared inputs sidecar " + key)
    frozen_capture, _ = _frozen_active_prerequisites()
    expected_bindings = _active_binding_contracts(frozen_capture)
    bindings = _mapping(sidecar.get("bindings"), "prepared inputs sidecar bindings")
    if set(bindings) != set(expected_bindings):
        raise RuntimeBenchmarkAnalysisError("prepared inputs sidecar binding ids differ")
    for identifier, expected in expected_bindings.items():
        binding = _mapping(bindings.get(identifier), "prepared inputs sidecar binding")
        profile = _mapping(binding.get("profile"), "prepared inputs sidecar binding profile")
        _expect_hash(profile.get("sha256"), expected["profile_sha256"], "prepared inputs sidecar binding profile SHA-256")
        if _archive_closure(binding.get("archives"), "prepared inputs sidecar binding archives") != expected["archives"]:
            raise RuntimeBenchmarkAnalysisError("prepared inputs sidecar binding archive closure differs")
        seed = _mapping(binding.get("seed"), "prepared inputs sidecar binding seed")
        _expect_hash(seed.get("sha256"), expected["seed_sha256"], "prepared inputs sidecar binding seed SHA-256")
        _same(_integer(seed.get("bytes"), "prepared inputs sidecar binding seed bytes", minimum=1), expected["seed_bytes"], "prepared inputs sidecar binding seed bytes")


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


def _profile_identity_path(path: str) -> str:
    # Only classify the eight frozen mixed-generation names. Stored paths and
    # hashes remain original; no synthetic alias enters evidence or file lookup.
    if KIND != _CURRENT505_GROUND_BINDINGS["KIND"]:
        return path
    try:
        return _CURRENT505_GROUND_PROFILE_ALIASES[path]
    except KeyError as error:
        raise RuntimeBenchmarkAnalysisError("current505 frozen profile identity differs") from error


def _profiles(plan: dict[str, Any]) -> dict[tuple[str, int, str], dict[str, str]]:
    if KIND == _CURRENT510_BINDINGS["KIND"]:
        return _current510_profiles(plan)
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
        candidate_label = "mir5" if REPAIR_PROFILE_PREFIX == _R06_BINDINGS["REPAIR_PROFILE_PREFIX"] else "candidate"
        match = re.fullmatch(re.escape(REPAIR_PROFILE_PREFIX) + r"(published|" + candidate_label + r")-f210-2123\.json", _profile_identity_path(path))
        if match is None:
            raise RuntimeBenchmarkAnalysisError("repair profile arm differs")
        arm = "published" if match.group(1) == "published" else "candidate"
        key = ("repair-active", 0, arm)
        if key in answer:
            raise RuntimeBenchmarkAnalysisError("repair profile arm duplicates")
        answer[key] = {"path": path, "sha256": _sha256(row.get("sha256"), "repair profile SHA-256")}
    agriculture_profiles = _array(agriculture.get("profiles"), "agriculture profiles")
    if len(agriculture_profiles) != 6:
        raise RuntimeBenchmarkAnalysisError("agriculture profile count differs")
    expression = re.compile(re.escape(AGRICULTURE_PROFILE_PREFIX) + r"(published|candidate-defaults)-(1|32|128)-f210-2123\.json$")
    for entry in agriculture_profiles:
        row = _mapping(entry, "agriculture profile")
        path = _string(row.get("path"), "agriculture profile path")
        match = expression.search(_profile_identity_path(path))
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


def _current510_profiles(plan: dict[str, Any]) -> dict[tuple[str, int, str], dict[str, str]]:
    """Keep each published profile under its original 505 plan identity."""
    root = Path(__file__).resolve().parents[1]
    old_plan, old_sha = _read_json(root / _CURRENT505_GROUND_BINDINGS["PLAN_PATH"], MAX_PLAN_BYTES, "original published plan")
    try:
        select_cohort("current505-ground")
        old_profiles = _validate_plan(old_plan, old_sha)["profiles"]
    finally:
        select_cohort("current510-mixed")
    answer = {key: value for key, value in old_profiles.items() if key[2] == "published"}
    fixture = _mapping(plan.get("active_fixture_contract"), "current510 fixture contract")
    repair = _array(_mapping(fixture.get("repair"), "current510 repair").get("profiles"), "current510 repair profiles")
    agriculture = _array(_mapping(fixture.get("agriculture"), "current510 agriculture").get("profiles"), "current510 agriculture profiles")
    if len(repair) != 1 or len(agriculture) != 3:
        raise RuntimeBenchmarkAnalysisError("current510 candidate profile count differs")
    expected = {"tests/profiles/runtime510-repair-candidate-f210-2123.json": ("repair-active", 0, "candidate")}
    expected.update({f"tests/profiles/runtime510-agriculture-candidate-defaults-{tier}-f210-2123.json":
                     ("agriculture-active", tier, "candidate-defaults") for tier in (1, 32, 128)})
    for entry in repair + agriculture:
        row = _mapping(entry, "current510 candidate profile")
        path = _string(row.get("path"), "current510 profile path")
        if path not in expected or expected[path] in answer:
            raise RuntimeBenchmarkAnalysisError("current510 profile identity differs")
        answer[expected[path]] = {"path": path, "sha256": _sha256(row.get("sha256"), "current510 profile SHA-256"),
                                  "original_capture_sha256": _sha256(row.get("original_capture_profile_sha256"), "original capture profile SHA-256")}
    if len(answer) != 8:
        raise RuntimeBenchmarkAnalysisError("current510 mixed profile closure differs")
    return answer


def _frozen_mixed_prerequisites() -> dict[str, dict[str, Any]]:
    path = Path(__file__).resolve().parents[1] / _CURRENT510_BINDINGS["ACTIVE_PREREQUISITES_CAPSULE"]
    payload = _read_bounded(path, MAX_ACTIVE_PREREQUISITES_CAPSULE_BYTES, "current510 prerequisite capsule")
    _expect_hash(hashlib.sha256(payload).hexdigest().upper(), _CURRENT510_BINDINGS["ACTIVE_PREREQUISITES_CAPSULE_SHA256"], "current510 prerequisite capsule SHA-256")
    try:
        capsule = json.loads(gzip.decompress(payload).decode("utf-8"), object_pairs_hook=_reject_duplicate_object, parse_constant=_reject_nonfinite_constant)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("current510 prerequisite capsule is not strict gzip JSON") from error
    _same(_integer(_mapping(capsule, "current510 capsule").get("schema"), "current510 capsule schema"), 1, "current510 capsule schema")
    _same(_string(capsule.get("kind"), "current510 capsule kind"), "MIR510MixedActiveRuntimePrerequisiteReceiptCapsuleV1", "current510 capsule kind")
    entries = _array(capsule.get("files"), "current510 capsule files")
    expected = {"original/active-seed-captures.json": _CURRENT505_GROUND_BINDINGS["ACTIVE_SEED_CAPTURE_SHA256"],
                "original/active-marker-pilots.json": _CURRENT505_GROUND_BINDINGS["MARKER_PILOT_SHA256"],
                "candidate/original-origins.json": _CURRENT510_ORIGINS_SHA256,
                "candidate/formal-marker-pilots.json": _CURRENT510_PILOT_SHA256}
    records = {}
    for entry in entries:
        row = _mapping(entry, "current510 capsule entry")
        name = _string(row.get("path"), "current510 capsule path")
        if name not in expected or name in records:
            raise RuntimeBenchmarkAnalysisError("current510 prerequisite capsule closure differs")
        try:
            raw = base64.b64decode(_string(row.get("base64"), "current510 capsule body"), validate=True)
            record = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_object, parse_constant=_reject_nonfinite_constant)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeBenchmarkAnalysisError("current510 prerequisite body differs") from error
        _same(_integer(row.get("bytes"), "current510 capsule bytes", minimum=1), len(raw), "current510 capsule bytes")
        _expect_hash(row.get("sha256"), expected[name], "current510 capsule declared hash")
        _expect_hash(hashlib.sha256(raw).hexdigest().upper(), expected[name], "current510 capsule body hash")
        records[name] = _mapping(record, "current510 prerequisite record")
    if set(records) != set(expected):
        raise RuntimeBenchmarkAnalysisError("current510 prerequisite body closure differs")
    return records


def _staged_profile_path(value: Any, expected_relative: str, label: str) -> None:
    """Require a staged Windows profile locator ending in the fixed repo path."""
    actual = _string(value, label).replace("\\", "/")
    expected = expected_relative.replace("\\", "/")
    if re.fullmatch(r"[A-Za-z]:/.*", actual) is None or not actual.endswith("/" + expected):
        raise RuntimeBenchmarkAnalysisError(label + " differs from the staged fixed profile")


def _validate_plan(plan: dict[str, Any], plan_sha256: str) -> dict[str, Any]:
    _expect_hash(plan_sha256, PLAN_SHA256, "raw R06 plan SHA-256")
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
    _same(_string(candidate.get("asset_root"), "candidate asset root"), ASSET_ROOT, "candidate asset root")
    _expect_hash(candidate.get("asset_inventory_file_sha256"), INVENTORY_SHA256, "candidate inventory SHA-256")
    _expect_hash(candidate.get("asset_inventory_content_sha256"), INVENTORY_CONTENT_SHA256, "candidate inventory content SHA-256")
    candidate_archive = _mapping(candidate.get("f210_archive"), "candidate F210 archive")
    _same(_string(candidate_archive.get("name"), "candidate archive name"), CANDIDATE_LEAF, "candidate archive name")
    _same(_integer(candidate_archive.get("bytes"), "candidate archive bytes", minimum=1), CANDIDATE_BYTES, "candidate archive bytes")
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
    # D6 names this metric with "ms"; observed/result fields spell out the unit.
    _same(_array(increment_rule.get("metrics"), "agriculture increment metrics"), ["engine_reported_average_ms_per_tick", *METRICS[1:]], "agriculture increment metrics")
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
    for name, expected_profiles in (("repair", 1 if KIND == _CURRENT510_BINDINGS["KIND"] else 2), ("agriculture", 3 if KIND == _CURRENT510_BINDINGS["KIND"] else 6)):
        row = _mapping(fixture.get(name), f"{name} fixture")
        _same(_array(row.get("required_markers"), f"{name} markers"), ["prepared", "start", "complete"], f"{name} markers")
        if len(_array(row.get("profiles"), f"{name} profiles")) != expected_profiles:
            raise RuntimeBenchmarkAnalysisError(f"{name} profile count differs")
    capture = _mapping(plan.get("active_seed_capture"), "active seed capture")
    _same(_integer(_mapping(capture.get("repair"), "repair capture").get("count"), "repair capture count"), 1 if KIND == _CURRENT510_BINDINGS["KIND"] else 2, "repair capture count")
    _same(_integer(_mapping(capture.get("agriculture"), "agriculture capture").get("count"), "agriculture capture count"), 3 if KIND == _CURRENT510_BINDINGS["KIND"] else 6, "agriculture capture count")
    _same(_string(capture.get("closed_save_name"), "active save name"), "mir5-native-active.zip", "active save name")
    _same(_boolean(capture.get("preparation_outside_timed_benchmark"), "capture preparation boundary"), True, "capture preparation boundary")
    pilot = _mapping(plan.get("unscored_marker_pilot"), "marker pilot")
    _same(_integer(pilot.get("count"), "marker pilot count"), 4 if KIND == _CURRENT510_BINDINGS["KIND"] else 8, "marker pilot count")
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


def _validate_capture_reference(
    value: Any,
    plan_sha256: str,
    profiles: dict[tuple[str, int, str], dict[str, str]],
    frozen_record: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    reference = _mapping(value, "active seed capture reference")
    _string(reference.get("path"), "active seed capture path")
    _expect_hash(reference.get("sha256"), ACTIVE_SEED_CAPTURE_SHA256, "active seed capture SHA-256")
    _same(_string(reference.get("kind"), "active seed capture kind"), CAPTURE_KIND, "active seed capture kind")
    _same(_string(reference.get("status"), "active seed capture status"), "prepared-active-saves-not-a-benchmark-result", "active seed capture status")
    record = _mapping(reference.get("record"), "active seed capture record")
    _same_json(record, frozen_record, "active seed capture record")
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


def _validate_pilot_witness(row: dict[str, Any], active: dict[str, Any]) -> None:
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


def _validate_pilot_reference(
    value: Any,
    plan_sha256: str,
    capture_reference: dict[str, Any],
    captures: dict[str, dict[str, Any]],
    frozen_record: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    reference = _mapping(value, "marker pilot reference")
    _string(reference.get("path"), "marker pilot path")
    _expect_hash(reference.get("sha256"), MARKER_PILOT_SHA256, "marker pilot SHA-256")
    _same(_string(reference.get("kind"), "marker pilot kind"), PILOT_KIND, "marker pilot kind")
    _same(_string(reference.get("status"), "marker pilot status"), "complete-unscored-not-a-performance-result", "marker pilot status")
    record = _mapping(reference.get("record"), "marker pilot record")
    _same_pilot_record(record, frozen_record, "marker pilot record")
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
        _validate_pilot_witness(row, active)
        _string(row.get("stdout"), "marker pilot stdout path")
        _sha256(row.get("stdout_sha256"), "marker pilot stdout SHA-256")
    return {
        active["id"]: _mapping(pilots[active["id"]].get("native_result"), "marker pilot native result")
        for active in _active_rows()
    }


def _verified_file(path: Any, digest: Any, label: str, size: int | None = None) -> Path:
    value = Path(_string(path, label + " path"))
    expected = _sha256(digest, label + " SHA-256")
    try:
        if not value.is_file():
            raise OSError("not a regular file")
        if size is not None and value.stat().st_size != size:
            raise RuntimeBenchmarkAnalysisError(label + " size differs")
        hasher = hashlib.sha256()
        with value.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                hasher.update(chunk)
    except OSError as error:
        raise RuntimeBenchmarkAnalysisError(label + " body is unavailable") from error
    _expect_hash(hasher.hexdigest().upper(), expected, label + " bytes")
    return value


def _verified_json_reference(reference: Any, label: str) -> dict[str, Any]:
    ref = _mapping(reference, label)
    path = _verified_file(ref.get("path"), ref.get("sha256"), label)
    value, _ = _read_json(path, 8 * 1024 * 1024, label)
    return value


def _validate_fixture_members(fixture: dict[str, Any], plan: dict[str, Any], kind: str, arm: str, tier: int) -> None:
    name = _string(fixture.get("name"), "fixture member name")
    version = _string(fixture.get("version"), "fixture member version")
    groups = {
        "mir-fixture-mir5-repair-stress": ("repair-stress", "repair-published" if arm == "published" else "repair-candidate"),
        "mir-fixture-mir5-repair-stress-active": ("repair-active",),
        "mir-fixture-mir5-active-mods-observer": ("active-mods-observer",),
        "mir-fixture-mir5-agriculture-scale": ("agriculture-core",),
        "mir-fixture-mir5-agriculture-scale-paired": ("agriculture-paired",),
        "mir-fixture-mir5-agriculture-scale-arm-published": ("agriculture-arm-published",),
        "mir-fixture-mir5-agriculture-scale-arm-candidate-defaults": ("agriculture-arm-candidate-defaults",),
        "mir-fixture-mir5-agriculture-scale-active": ("agriculture-active",),
        f"mir-fixture-mir5-agriculture-scale-matched-tier-{tier}": (f"agriculture-tier-{tier}",),
    }
    if name not in groups:
        raise RuntimeBenchmarkAnalysisError("fixture member name is outside the selected finite closure")
    contract = _mapping(_mapping(plan.get("active_fixture_contract"), "fixture member contract").get(kind), "fixture member set")
    expected = {}
    for item in _array(contract.get("fixture_source_members"), "fixture source members"):
        if item.get("fixture") in groups[name]:
            member = _string(item.get("member"), "fixture member path")
            if member in expected or "/" in member or "\\" in member:
                raise RuntimeBenchmarkAnalysisError("fixture member declaration differs")
            expected[member] = _sha256(item.get("sha256"), "fixture member hash")
    if not expected:
        raise RuntimeBenchmarkAnalysisError("fixture member declaration is absent")
    archive_path = _string(fixture.get("archive", fixture.get("path")), "fixture archive path")
    try:
        with zipfile.ZipFile(archive_path) as archive:
            entries = archive.infolist()
            root = f"{name}_{version}/"
            if len(entries) != len(expected) or any(entry.is_dir() or not entry.filename.startswith(root) for entry in entries):
                raise RuntimeBenchmarkAnalysisError("fixture archive member closure differs")
            names = [entry.filename[len(root):] for entry in entries]
            if len(set(names)) != len(names) or set(names) != set(expected):
                raise RuntimeBenchmarkAnalysisError("fixture archive member names differ")
            for entry, member in zip(entries, names, strict=True):
                if entry.file_size > 8 * 1024 * 1024:
                    raise RuntimeBenchmarkAnalysisError("fixture archive member exceeds bound")
                _expect_hash(hashlib.sha256(archive.read(entry)).hexdigest().upper(), expected[member], "fixture archive member")
    except (OSError, zipfile.BadZipFile, RuntimeError) as error:
        if isinstance(error, RuntimeBenchmarkAnalysisError):
            raise
        raise RuntimeBenchmarkAnalysisError("fixture archive body differs") from error


def _verify_current510_controller_file(path: Path | None) -> None:
    if path is None:
        raise RuntimeBenchmarkAnalysisError("current510 requires an explicit retained controller source file")
    _verified_file(str(path), _CURRENT510_CONTROLLER_SHA256, "current510 retained controller bytes")


def _validate_current510_origin(row: dict[str, Any], expected: dict[str, Any], profile: dict[str, str], plan: dict[str, Any]) -> dict[str, Any]:
    for key in ("id", "kind", "arm", "tier"):
        _same(row.get(key), expected[key], "current510 origin " + key)
    harness = _mapping(row.get("source_harness"), "current510 origin harness")
    wanted_harness = ({"commit": "063c99cb209a16ac26c30560e9bbef0a41c957e8", "tree": "9130eb22aa1c1c8f8384cecf9dce9ec15ae15b4b"}
                      if expected["kind"] == "repair-stress" else
                      {"commit": "280230f95223f0dbd7c851d5a1840ee0e5e0d5f3", "tree": PLAN_TREE})
    _same_json(harness, wanted_harness, "current510 original harness")
    original_profile = _mapping(row.get("profile"), "current510 original profile")
    _expect_hash(original_profile.get("sha256"), profile["original_capture_sha256"], "current510 original profile hash")
    original = _verified_json_reference(original_profile, "current510 original profile")
    canonical_path = Path(__file__).resolve().parents[1] / profile["path"]
    canonical, canonical_sha = _read_json(canonical_path, MAX_PLAN_BYTES, "current510 canonical profile")
    _expect_hash(canonical_sha, profile["sha256"], "current510 canonical profile hash")
    _same_json(original, canonical, "current510 normalized profile contents")
    archive = _mapping(row.get("mir_archive"), "current510 origin player")
    _expect_hash(archive.get("sha256"), CANDIDATE_SHA256, "current510 origin player hash")
    _same(_integer(archive.get("bytes"), "current510 origin player bytes"), CANDIDATE_BYTES, "current510 origin player bytes")
    _verified_file(archive.get("path"), archive.get("sha256"), "current510 origin player", CANDIDATE_BYTES)
    engine = _mapping(row.get("engine"), "current510 origin engine")
    _expect_hash(engine.get("sha256"), ENGINE_SHA256, "current510 origin engine hash")
    _same(_string(engine.get("product_version"), "current510 engine version"), "2.1.23", "current510 engine version")
    _same(_string(engine.get("base_version"), "current510 base version"), "2.1.23", "current510 base version")
    _verified_file(engine.get("path"), engine.get("sha256"), "current510 origin engine")
    seed = _mapping(row.get("active_seed"), "current510 original seed")
    _verified_file(seed.get("path"), seed.get("sha256"), "current510 original seed", _integer(seed.get("bytes"), "current510 seed bytes", minimum=1))
    native_ref = _mapping(row.get("native_result"), "current510 native result")
    native = _verified_json_reference(native_ref, "current510 native result")
    mirror_ref = _mapping(row.get("primary_mirror"), "current510 native mirror")
    mirror = _verified_json_reference(mirror_ref, "current510 native mirror")
    _same_json(mirror, native, "current510 original and mirrored native result")
    _same(_boolean(mirror_ref.get("parsed_equal_original"), "current510 native mirror parsed equality"), True, "current510 native mirror parsed equality")
    _same(_boolean(mirror_ref.get("byte_identical"), "current510 native mirror byte equality"), mirror_ref.get("sha256") == native_ref.get("sha256"), "current510 native mirror byte equality")
    repository = Path(__file__).resolve().parents[1]
    try:
        tree = subprocess.check_output(["git", "-C", str(repository), "rev-parse", wanted_harness["commit"] + "^{tree}"], stderr=subprocess.DEVNULL, text=True).strip()
        harness_raw = subprocess.check_output(["git", "-C", str(repository), "show", wanted_harness["commit"] + ":tools/Invoke-NativeFixture.ps1"], stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeBenchmarkAnalysisError("current510 original source Git objects unavailable") from error
    _same(tree, wanted_harness["tree"], "current510 original source tree")
    _expect_hash(hashlib.sha256(harness_raw).hexdigest().upper(), native.get("harness_sha256"), "current510 native harness bytes")
    _same(_string(native_ref.get("status"), "current510 native status"), "passed-private-native-active-seed-preparation", "current510 native status")
    _same(_string(native.get("status"), "current510 native body status"), "passed-private-native-active-seed-preparation", "current510 native body status")
    _same(_string(native.get("source_head"), "current510 native source"), wanted_harness["commit"], "current510 native source")
    _same(_boolean(native.get("source_dirty"), "current510 native dirty"), False, "current510 native dirty")
    for name, wanted in (("profile", original_profile), ("mir_archive", archive), ("engine", engine), ("active_seed", seed)):
        actual = _mapping(native.get(name), "current510 native " + name)
        _same(_string(actual.get("path"), "current510 native path"), _string(wanted.get("path"), "current510 original path"), "current510 native path")
        _expect_hash(actual.get("sha256"), wanted.get("sha256"), "current510 native " + name + " hash")
    _same(_string(_mapping(native.get("library_control_restoration"), "current510 capture restoration").get("status"), "current510 capture restoration status"), "restored-direct-library-controls", "current510 capture restoration status")
    marker = _mapping(_mapping(native.get("active_preparation"), "current510 native preparation").get("marker"), "current510 native marker")
    _same_json(marker, row.get("prepared_marker"), "current510 original prepared marker")
    _validate_prepared_witness(_marker(marker, "current510 prepared marker", expected["kind"], "prepared", "pending"), expected)
    fixtures = _array(row.get("fixtures"), "current510 origin fixtures")
    expected_count = 3 if expected["kind"] == "repair-stress" else 6
    if len(fixtures) != expected_count:
        raise RuntimeBenchmarkAnalysisError("current510 origin fixture count differs")
    selected = {(item["name"], item["version"]) for item in canonical["mods"] if item["enabled"] and item["name"].startswith("mir-fixture-")}
    fixture_ids = set()
    native_fixtures = _array(native.get("fixtures"), "current510 native fixtures")
    for value in fixtures:
        fixture = _mapping(value, "current510 origin fixture")
        name, version = _string(fixture.get("name"), "current510 fixture name"), _string(fixture.get("version"), "current510 fixture version")
        if (name, version) in fixture_ids:
            raise RuntimeBenchmarkAnalysisError("current510 origin fixture duplicates")
        fixture_ids.add((name, version))
        _verified_file(fixture.get("path"), fixture.get("sha256"), "current510 fixture", _integer(fixture.get("bytes"), "current510 fixture bytes", minimum=1))
        _validate_fixture_members(fixture, plan, "repair" if expected["kind"] == "repair-stress" else "agriculture", expected["arm"], expected["tier"])
        if PureWindowsPath(_string(fixture.get("path"), "current510 fixture path")).name != f"{name}_{version}.zip":
            raise RuntimeBenchmarkAnalysisError("current510 fixture filename differs")
        matches = [item for item in native_fixtures if item.get("archive") == fixture["path"] and item.get("sha256") == fixture["sha256"]]
        if len(matches) != 1:
            raise RuntimeBenchmarkAnalysisError("current510 native fixture identity differs")
    if fixture_ids != selected or len(native_fixtures) != expected_count:
        raise RuntimeBenchmarkAnalysisError("current510 selected fixture closure differs")
    logs = _array(row.get("raw_logs"), "current510 original logs")
    if len(logs) < 3:
        raise RuntimeBenchmarkAnalysisError("current510 original logs are incomplete")
    for entry in logs:
        log = _mapping(entry, "current510 original log")
        _verified_file(log.get("path"), log.get("sha256"), "current510 original log", _integer(log.get("bytes"), "current510 original log bytes", minimum=1))
    marker_leaf = "create.factorio.log" if expected["kind"] == "repair-stress" else "active-prepare.factorio.log"
    marker_logs = [entry for entry in logs if PureWindowsPath(entry["path"]).name == marker_leaf]
    if len(marker_logs) != 1:
        raise RuntimeBenchmarkAnalysisError("current510 original marker log differs")
    try:
        log_text = _read_bounded(Path(marker_logs[0]["path"]), 16 * 1024 * 1024, "current510 prepared log").decode("utf-8")
        markers = [json.loads(value) for value in re.findall(r"\[MIR5_RUNTIME_ACTIVE\] (\{[^\r\n]+\})", log_text)]
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("current510 prepared marker log differs") from error
    if re.search(r"(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$", log_text):
        raise RuntimeBenchmarkAnalysisError("current510 prepared log contains fatal diagnostics")
    matches = [marker for marker in markers if marker.get("kind") == expected["kind"] and marker.get("stage") == "prepared"]
    if len(matches) != 1:
        raise RuntimeBenchmarkAnalysisError("current510 raw prepared marker differs")
    _same_json(matches[0], marker, "current510 raw prepared marker")
    return row


def _verify_pilot_files(row: dict[str, Any], root: Path, expected: dict[str, Any]) -> None:
    for field, label in (("fixture_log", "pilot log"), ("stdout", "pilot stdout")):
        relative = Path(_string(row.get(field), label + " path"))
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeBenchmarkAnalysisError(label + " path escapes receipt")
        _verified_file(str(root / relative), row.get(field + "_sha256"), label)
    log = root / row["fixture_log"]
    try:
        text = _read_bounded(log, 16 * 1024 * 1024, "pilot log").decode("utf-8")
        matches = [json.loads(value) for value in re.findall(r"\[MIR5_RUNTIME_ACTIVE\] (\{[^\r\n]+\})", text)]
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("pilot marker log differs") from error
    if re.search(r"(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$", text):
        raise RuntimeBenchmarkAnalysisError("pilot log contains fatal diagnostics")
    for stage in ("start", "complete"):
        selected = [item for item in matches if item.get("kind") == expected["kind"] and item.get("stage") == stage]
        if len(selected) != 1:
            raise RuntimeBenchmarkAnalysisError("pilot raw marker count differs")
        _same_json(selected[0], row[stage + "_marker"], "pilot raw " + stage + " marker")


def _validate_current510_mixed(result: dict[str, Any], profiles: dict[tuple[str, int, str], dict[str, str]]) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], dict[str, Any]]:
    frozen = _frozen_mixed_prerequisites()
    mixed = _mapping(result.get("mixed_prerequisites"), "current510 mixed prerequisites")
    published = _mapping(mixed.get("published"), "current510 published prerequisites")
    candidate = _mapping(mixed.get("candidate"), "current510 candidate prerequisites")
    old_capture = _mapping(published.get("capture"), "original published capture")
    old_pilot = _mapping(published.get("pilot"), "original published pilot")
    _verified_file(old_capture.get("path"), old_capture.get("sha256"), "original published capture", 72034)
    _verified_file(old_pilot.get("path"), old_pilot.get("sha256"), "original published pilot", 149669)
    _same_json(old_capture.get("record"), frozen["original/active-seed-captures.json"], "original published capture")
    _same_pilot_record(old_pilot.get("record"), frozen["original/active-marker-pilots.json"], "original published pilot")
    old_plan_wrapper = _mapping(published.get("plan"), "original published plan reference")
    _expect_hash(old_plan_wrapper.get("sha256"), _CURRENT505_GROUND_BINDINGS["PLAN_SHA256"], "original published plan hash")
    _same(_string(old_plan_wrapper.get("source_revision"), "original published plan revision"), _CURRENT505_GROUND_BINDINGS["PLAN_REVISION"], "original published plan revision")
    old_plan, old_sha = _read_json(Path(__file__).resolve().parents[1] / _CURRENT505_GROUND_BINDINGS["PLAN_PATH"], MAX_PLAN_BYTES, "original published plan")
    _same_json(old_plan_wrapper.get("plan"), old_plan, "original published plan")
    _same(_string(old_plan_wrapper.get("active_cohort"), "original published cohort"), "current505-ground-r02", "original published cohort")
    old_helpers = _array(published.get("raw_helpers"), "original published raw helpers")
    expected_helpers = {item["path"]: item["sha256"] for item in old_plan["public_harness"]["git_blob_sha256"]}
    if len(old_helpers) != 12 or {item.get("path") for item in old_helpers} != set(expected_helpers):
        raise RuntimeBenchmarkAnalysisError("original published raw helper closure differs")
    old_stage = Path(_string(published.get("raw_helper_stage"), "original published helper stage"))
    for helper in old_helpers:
        digest = expected_helpers[helper["path"]]
        _expect_hash(helper.get("raw_git_sha256"), digest, "original helper raw Git")
        _expect_hash(helper.get("executed_sha256"), digest, "original helper executed")
        _verified_file(str(old_stage / helper["path"]), digest, "original helper", _integer(helper.get("bytes"), "original helper bytes", minimum=1))
    try:
        select_cohort("current505-ground")
        old_contract = _validate_plan(old_plan, old_sha)
        capture_ref = {**old_capture, "kind": CAPTURE_KIND, "status": "prepared-active-saves-not-a-benchmark-result"}
        pilot_ref = {**old_pilot, "kind": PILOT_KIND, "status": "complete-unscored-not-a-performance-result"}
        old_rows = _validate_capture_reference(capture_ref, old_sha, old_contract["profiles"], frozen["original/active-seed-captures.json"])
        old_pilots = _validate_pilot_reference(pilot_ref, old_sha, capture_ref, old_rows, frozen["original/active-marker-pilots.json"])
    finally:
        select_cohort("current510-mixed")
    captures = {key: value for key, value in old_rows.items() if value["arm"] == "published"}
    pilot_native = {key: old_pilots[key] for key in captures}
    expected_rows = {item["id"]: item for item in _active_rows()}
    for identifier, row in captures.items():
        original_pilot = next(item for item in frozen["original/active-marker-pilots.json"]["observations"] if item["id"] == identifier)
        _verify_pilot_files(original_pilot, Path(old_pilot["path"]).parent, next(item for item in _active_rows() if item["id"] == identifier))
        pilot_sample = _mapping(original_pilot.get("native_result"), "published pilot native")
        _same(_string(pilot_sample.get("kind"), "published pilot native kind"), PILOT_KIND, "published pilot native kind")
        _same(_string(pilot_sample.get("status"), "published pilot native status"), "unscored-marker-pilot-not-a-performance-result", "published pilot native status")
        _same(_boolean(pilot_sample.get("scored"), "published pilot scored"), False, "published pilot scored")
        for flag in ("performance_acceptance", "release_qualification"):
            _same(_boolean(pilot_sample.get(flag), "published pilot " + flag), False, "published pilot " + flag)
        _same(_array(pilot_sample.get("command"), "published pilot command"), ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"], "published pilot command")
        pilot_seed = _mapping(pilot_sample.get("seed"), "published pilot seed")
        _same(_string(pilot_seed.get("source_path"), "published pilot seed path"), row["active_seed"]["path"], "published pilot seed path")
        for field in ("source_sha256", "owned_sha256"):
            _expect_hash(pilot_seed.get(field), row["active_seed"]["sha256"], "published pilot seed " + field)
        _verified_file(pilot_seed.get("owned_path"), pilot_seed.get("owned_sha256"), "published pilot owned seed", row["active_seed"]["bytes"])
        integrity = _mapping(pilot_sample.get("seed_integrity_after_sample"), "published pilot seed integrity")
        _same(_string(integrity.get("sample_id"), "published pilot integrity id"), "pilot-" + identifier, "published pilot integrity id")
        for side in ("source", "owned"):
            checked = _mapping(integrity.get(side), "published pilot integrity " + side)
            _same(_boolean(checked.get("unchanged"), "published pilot seed unchanged"), True, "published pilot seed unchanged")
            for field in ("expected_sha256", "actual_sha256"):
                _expect_hash(checked.get(field), row["active_seed"]["sha256"], "published pilot integrity " + field)
        pilot_profile = _mapping(pilot_sample.get("profile"), "published pilot profile")
        _expect_hash(pilot_profile.get("sha256"), row["profile"]["sha256"], "published pilot profile")
        _verified_file(pilot_profile.get("path"), pilot_profile.get("sha256"), "published pilot profile")
        _expect_hash(_mapping(pilot_sample.get("engine"), "published pilot engine").get("sha256"), ENGINE_SHA256, "published pilot engine")
        expected_archives = dict(row["profile"]["selection"]["archive_sha256"])
        for fixture in row["fixtures"]:
            expected_archives[PureWindowsPath(fixture["archive"]).name] = fixture["sha256"]
        if _archive_closure(pilot_sample.get("archives"), "published pilot archive closure") != expected_archives:
            raise RuntimeBenchmarkAnalysisError("published pilot archive closure differs")
        restoration = _mapping(pilot_sample.get("library_control_restoration"), "published pilot restoration")
        _same(_string(restoration.get("status"), "published pilot restoration status"), "restored-direct-library-controls", "published pilot restoration status")
        _expect_hash(restoration.get("profile_sha256"), row["profile"]["sha256"], "published pilot restoration profile")
        _verified_file(row["active_seed"]["path"], row["active_seed"]["sha256"], "published seed", row["active_seed"]["bytes"])
        native_path = _verified_file(row["native_result_path"], row["native_result_sha256"], "published native result")
        native, _ = _read_json(native_path, 8 * 1024 * 1024, "published native result")
        _same(_string(native.get("source_head"), "published native source"), _CURRENT505_GROUND_BINDINGS["PLAN_SOURCE"], "published native source")
        _same(_string(native.get("status"), "published native status"), "passed-private-native-active-seed-preparation", "published native status")
        old_archive = _mapping(native.get("mir_archive"), "published native archive")
        _expect_hash(old_archive.get("sha256"), PUBLISHED_SHA256, "published native archive")
        _verified_file(old_archive.get("path"), old_archive.get("sha256"), "published player archive")
        old_engine = _mapping(native.get("engine"), "published native engine")
        _expect_hash(old_engine.get("sha256"), ENGINE_SHA256, "published native engine")
        _verified_file(old_engine.get("path"), old_engine.get("sha256"), "published engine")
        _verified_file(row["profile"]["path"], row["profile"]["sha256"], "published capture profile")
        _expect_hash(_mapping(native.get("profile"), "published native profile").get("sha256"), row["profile"]["sha256"], "published native profile")
        _expect_hash(_mapping(native.get("active_seed"), "published native seed").get("sha256"), row["active_seed"]["sha256"], "published native seed")
        _same_json(_mapping(native.get("active_preparation"), "published native preparation").get("marker"), row["prepared_marker"], "published native prepared marker")
        for fixture in row["fixtures"]:
            _verified_file(fixture["archive"], fixture["sha256"], "published fixture", fixture["bytes"])
            _validate_fixture_members(fixture, old_plan, row["fixture"], row["arm"], row["tier"])
    origin_ref = _mapping(candidate.get("origins"), "current510 candidate origins")
    pilot_ref = _mapping(candidate.get("pilot"), "current510 candidate pilot")
    _expect_hash(origin_ref.get("sha256"), _CURRENT510_ORIGINS_SHA256, "current510 origin receipt")
    _expect_hash(pilot_ref.get("sha256"), _CURRENT510_PILOT_SHA256, "current510 pilot receipt")
    _verified_file(origin_ref.get("path"), origin_ref.get("sha256"), "current510 origin receipt", 28067)
    _verified_file(pilot_ref.get("path"), pilot_ref.get("sha256"), "current510 pilot receipt", 72302)
    origin = _mapping(origin_ref.get("record"), "current510 origin record")
    pilot = _mapping(pilot_ref.get("record"), "current510 pilot record")
    _same_json(origin, frozen["candidate/original-origins.json"], "current510 origin record")
    _same_pilot_record(pilot, frozen["candidate/formal-marker-pilots.json"], "current510 formal pilot record")
    _same(_string(origin.get("kind"), "current510 origin kind"), "MIR5RuntimeBenchmark510CandidateOriginsV1", "current510 origin kind")
    _same(_string(origin.get("status"), "current510 origin status"), "validated-original-candidate-origins-not-a-benchmark-result", "current510 origin status")
    origin_plan = _mapping(origin.get("plan"), "current510 origin plan")
    _expect_hash(origin_plan.get("sha256"), PLAN_SHA256, "current510 origin plan")
    _same(_string(origin_plan.get("path"), "current510 origin plan path"), PLAN_PATH, "current510 origin plan path")
    _same(_string(origin_plan.get("revision"), "current510 origin plan revision"), PLAN_REVISION, "current510 origin plan revision")
    _same(_string(pilot.get("kind"), "current510 pilot kind"), "MIR5RuntimeBenchmark510CandidateMarkerPilotV1", "current510 pilot kind")
    _same(_string(pilot.get("status"), "current510 pilot status"), "complete-unscored-not-a-performance-result", "current510 pilot status")
    _expect_hash(pilot.get("plan_sha256"), PLAN_SHA256, "current510 pilot plan")
    _expect_hash(_mapping(pilot.get("candidate_origins"), "current510 pilot origins").get("sha256"), _CURRENT510_ORIGINS_SHA256, "current510 pilot origins")
    _same(_string(pilot.get("stage_checkout_revision"), "current510 pilot stage revision"), PLAN_REVISION, "current510 pilot stage revision")
    _same(_string(pilot.get("public_harness_revision"), "current510 pilot harness revision"), PLAN_SOURCE, "current510 pilot harness revision")
    controller = _mapping(pilot.get("private_controller"), "current510 pilot controller")
    _same(_string(controller.get("revision"), "current510 pilot controller revision"), "31afde91573c02027b6a3de058e12fd1d343488e", "current510 pilot controller revision")
    _expect_hash(controller.get("raw_git_sha256"), "0CDA2B041F2198E1AF66EA7B73452C218A224D8A38BAE0DB60A33DDE3E764728", "current510 pilot controller raw")
    _expect_hash(controller.get("executed_sha256"), controller.get("raw_git_sha256"), "current510 pilot controller executed")
    _same(_boolean(controller.get("executed_matches_raw_git"), "current510 pilot controller equality"), True, "current510 pilot controller equality")
    _same(_integer(pilot.get("schedule_launches"), "current510 pilot schedule launches"), 0, "current510 pilot schedule launches")
    for record in (origin, pilot):
        _same(_boolean(record.get("performance_acceptance"), "current510 prerequisite performance"), False, "current510 prerequisite performance")
        _same(_boolean(record.get("release_qualification"), "current510 prerequisite release"), False, "current510 prerequisite release")
    candidates = _array(origin.get("rows"), "current510 origin rows")
    pilots = _array(pilot.get("observations"), "current510 pilot rows")
    candidate_ids = {key for key, value in expected_rows.items() if value["arm"] != "published"}
    if len(candidates) != 4 or len(pilots) != 4 or {item.get("id") for item in candidates} != candidate_ids or {item.get("id") for item in pilots} != candidate_ids:
        raise RuntimeBenchmarkAnalysisError("current510 candidate prerequisite rows differ")
    for value in candidates:
        row = _mapping(value, "current510 origin row")
        expected = expected_rows[row["id"]]
        scenario = "repair-active" if expected["kind"] == "repair-stress" else "agriculture-active"
        _validate_current510_origin(row, expected, profiles[(scenario, expected["tier"], expected["arm"])], _read_json(Path(__file__).resolve().parents[1] / PLAN_PATH, MAX_PLAN_BYTES, "current510 plan")[0])
        captures[row["id"]] = row
    for value in pilots:
        row = _mapping(value, "current510 pilot row")
        expected = expected_rows[row["id"]]
        for key in ("kind", "arm", "tier"):
            _same(row.get(key), expected[key], "current510 pilot " + key)
        _validate_pilot_witness(row, expected)
        _same_json(row.get("prepared_marker"), captures[row["id"]]["prepared_marker"], "current510 pilot prepared marker")
        sample = _mapping(row.get("native_result"), "current510 pilot native")
        _same(_string(sample.get("kind"), "current510 pilot native kind"), PILOT_KIND, "current510 pilot native kind")
        _same(_string(sample.get("status"), "current510 pilot native status"), "unscored-marker-pilot-not-a-performance-result", "current510 pilot native status")
        _same(_boolean(sample.get("scored"), "current510 pilot scored"), False, "current510 pilot scored")
        for flag in ("performance_acceptance", "release_qualification"):
            _same(_boolean(sample.get(flag), "current510 pilot " + flag), False, "current510 pilot " + flag)
        _same(_string(sample.get("id"), "current510 pilot native id"), "pilot-" + row["id"], "current510 pilot native id")
        _same(_array(sample.get("command"), "current510 pilot command"), ["--benchmark", "<fresh-owned-active-seed.zip>", "--benchmark-ticks", "25000", "--benchmark-runs", "1", "--benchmark-sanitize"], "current510 pilot command")
        origin_row = captures[row["id"]]
        origin_seed = origin_row["active_seed"]
        seed = _mapping(sample.get("seed"), "current510 pilot seed")
        _same(_string(seed.get("source_path"), "current510 pilot source path"), origin_seed["path"], "current510 pilot source path")
        for field in ("source_sha256", "owned_sha256"):
            _expect_hash(seed.get(field), origin_seed["sha256"], "current510 pilot seed " + field)
        _verified_file(seed.get("owned_path"), seed.get("owned_sha256"), "current510 pilot owned seed", origin_seed["bytes"])
        integrity = _mapping(sample.get("seed_integrity_after_sample"), "current510 pilot seed integrity")
        _same(_string(integrity.get("sample_id"), "current510 pilot integrity id"), "pilot-" + row["id"], "current510 pilot integrity id")
        for side in ("source", "owned"):
            check = _mapping(integrity.get(side), "current510 pilot " + side + " integrity")
            _same(_boolean(check.get("unchanged"), "current510 pilot unchanged"), True, "current510 pilot unchanged")
            for field in ("expected_sha256", "actual_sha256"):
                _expect_hash(check.get(field), origin_seed["sha256"], "current510 pilot integrity " + field)
        scenario = "repair-active" if expected["kind"] == "repair-stress" else "agriculture-active"
        expected_profile = profiles[(scenario, expected["tier"], expected["arm"])]
        sample_profile = _mapping(sample.get("profile"), "current510 pilot profile")
        _staged_profile_path(sample_profile.get("path"), expected_profile["path"], "current510 pilot profile")
        _expect_hash(sample_profile.get("sha256"), expected_profile["sha256"], "current510 pilot profile")
        _verified_file(sample_profile.get("path"), sample_profile.get("sha256"), "current510 pilot profile")
        _expect_hash(_mapping(sample.get("engine"), "current510 pilot engine").get("sha256"), ENGINE_SHA256, "current510 pilot engine")
        expected_archives = {CANDIDATE_LEAF: CANDIDATE_SHA256}
        for fixture in origin_row["fixtures"]:
            expected_archives[PureWindowsPath(fixture["path"]).name] = fixture["sha256"]
        if _archive_closure(sample.get("archives"), "current510 pilot archive closure") != expected_archives:
            raise RuntimeBenchmarkAnalysisError("current510 pilot archive closure differs")
        restoration = _mapping(sample.get("library_control_restoration"), "current510 pilot restoration")
        _same(_string(restoration.get("status"), "current510 pilot restoration status"), "restored-direct-library-controls", "current510 pilot restoration status")
        _expect_hash(restoration.get("profile_sha256"), expected_profile["sha256"], "current510 pilot restored profile")
        for field in ("dependency_payload_bytes_copied", "archive_links_created", "archive_extractions"):
            _same(_integer(restoration.get(field), "current510 pilot restoration " + field), 0, "current510 pilot restoration " + field)
        pilot_root = Path(_string(pilot_ref.get("path"), "current510 pilot receipt path")).parent
        _verify_pilot_files(row, pilot_root, expected)
        pilot_native[row["id"]] = sample
    if set(captures) != set(expected_rows) or set(pilot_native) != set(expected_rows):
        raise RuntimeBenchmarkAnalysisError("current510 mixed prerequisite closure differs")
    return captures, pilot_native, mixed


def _current510_row_provenance(captures: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    rows = {}
    for identifier, capture in captures.items():
        if capture["arm"] == "published":
            rows[identifier] = {"origin_kind": "original505-ground-r02", "source_harness": _CURRENT505_GROUND_BINDINGS["PLAN_SOURCE"],
                "capture_receipt_sha256": _CURRENT505_GROUND_BINDINGS["ACTIVE_SEED_CAPTURE_SHA256"], "pilot_receipt_sha256": _CURRENT505_GROUND_BINDINGS["MARKER_PILOT_SHA256"],
                "native_result_path": capture["native_result_path"], "native_result_sha256": capture["native_result_sha256"],
                "original_profile_sha256": capture["profile"]["sha256"], "seed": capture["active_seed"], "fixtures": capture["fixtures"]}
        else:
            fixtures = [{"archive": item["path"], "sha256": item["sha256"], "bytes": item["bytes"], "name": item["name"], "version": item["version"]} for item in capture["fixtures"]]
            rows[identifier] = {"origin_kind": "current510-original-candidate", "source_harness": capture["source_harness"],
                "capture_receipt_sha256": _CURRENT510_ORIGINS_SHA256, "pilot_receipt_sha256": _CURRENT510_PILOT_SHA256,
                "native_result_path": capture["native_result"]["path"], "native_result_sha256": capture["native_result"]["sha256"],
                "original_profile_sha256": capture["profile"]["sha256"], "canonical_profile_sha256": None,
                "seed": capture["active_seed"], "fixtures": fixtures}
    return rows


def _validate_current510_provenance(value: Any, captures: dict[str, dict[str, Any]], profiles: dict[tuple[str, int, str], dict[str, str]]) -> dict[str, dict[str, Any]]:
    expected = _current510_row_provenance(captures)
    for row in _active_rows():
        if row["arm"] != "published":
            scenario = "repair-active" if row["kind"] == "repair-stress" else "agriculture-active"
            expected[row["id"]]["canonical_profile_sha256"] = profiles[(scenario, row["tier"], row["arm"])]["sha256"]
    _same_json(value, expected, "current510 per-row provenance")
    return expected


def _validate_current510_custody(sample: dict[str, Any], schedule: dict[str, Any], provenance: dict[str, Any]) -> None:
    reference = _mapping(sample.get("fixture_custody"), "current510 fixture custody")
    path = PureWindowsPath(_string(reference.get("path"), "current510 custody path"))
    seed_path = PureWindowsPath(_string(_mapping(sample.get("seed"), "current510 custody seed").get("owned_path"), "current510 custody seed path"))
    if not path.is_absolute() or not seed_path.is_absolute() or len(seed_path.parents) < 7:
        raise RuntimeBenchmarkAnalysisError("current510 custody path differs")
    run_root = seed_path.parents[6]
    expected_path = run_root / "fixture-custody" / schedule["id"] / "fixture-custody-result.json"
    _same(path, expected_path, "current510 custody path")
    record = _mapping(reference.get("record"), "current510 custody record")
    on_disk = _verified_json_reference(reference, "current510 custody record")
    _same_json(record, on_disk, "current510 custody file")
    _same(_integer(record.get("schema"), "current510 custody schema"), 1, "current510 custody schema")
    _same(_string(record.get("kind"), "current510 custody kind"), "MIR5RuntimeBenchmark510FixtureCustodyV1", "current510 custody kind")
    _same(_boolean(record.get("body_succeeded"), "current510 custody body"), True, "current510 custody body")
    _same(_array(record.get("restoration_failures"), "current510 custody failures"), [], "current510 custody failures")
    reserve = _integer(record.get("reserved_mib"), "current510 custody reserve", minimum=1)
    if reserve >= 120:
        raise RuntimeBenchmarkAnalysisError("current510 custody reserve exceeds total budget")
    _same(_integer(sample.get("fixture_custody_reserve_mib"), "current510 sample custody reserve"), reserve, "current510 sample custody reserve")
    expected = {PureWindowsPath(item["archive"]).name: item for item in provenance["fixtures"]}
    fixtures = _array(record.get("fixtures"), "current510 custody fixtures")
    if len(expected) != len(provenance["fixtures"]) or len(fixtures) != len(expected):
        raise RuntimeBenchmarkAnalysisError("current510 custody fixture closure differs")
    seen = set()
    snapshot_bytes = 0
    for item in fixtures:
        row = _mapping(item, "current510 custody fixture")
        leaf = _string(row.get("leaf"), "current510 custody fixture leaf")
        if leaf not in expected or leaf in seen or PureWindowsPath(leaf).name != leaf:
            raise RuntimeBenchmarkAnalysisError("current510 custody fixture identity differs")
        seen.add(leaf)
        fixture = expected[leaf]
        _same(PureWindowsPath(_string(row.get("source"), "current510 fixture source")), PureWindowsPath(fixture["archive"]), "current510 fixture source")
        _same(PureWindowsPath(_string(row.get("destination"), "current510 fixture destination")), PureWindowsPath("D:/Projects/Factorio/testmods/2.1") / leaf, "current510 fixture destination")
        _expect_hash(row.get("selected_sha256"), fixture["sha256"], "current510 selected fixture")
        prior = _boolean(row.get("prior_exists"), "current510 fixture prior exists")
        prior_hash = row.get("prior_sha256")
        prior_bytes = _integer(row.get("prior_bytes"), "current510 fixture prior bytes", minimum=0)
        if prior:
            _sha256(prior_hash, "current510 prior fixture hash")
        else:
            _same(prior_hash, "", "current510 absent fixture hash")
            _same(prior_bytes, 0, "current510 absent fixture bytes")
        changed = _boolean(row.get("changed"), "current510 fixture changed")
        _same(changed, not prior or prior_hash != fixture["sha256"], "current510 fixture changed")
        _same(_string(row.get("restoration_status"), "current510 fixture restoration"), "verified", "current510 fixture restoration")
        _same(row.get("restored_sha256"), prior_hash, "current510 restored fixture hash")
        _same(_integer(row.get("restored_bytes"), "current510 restored fixture bytes", minimum=0), prior_bytes, "current510 restored fixture bytes")
        snapshot = row.get("snapshot")
        if changed and prior:
            _same(PureWindowsPath(_string(snapshot, "current510 fixture snapshot")), path.parent / "prior" / leaf, "current510 fixture snapshot")
            _verified_file(snapshot, prior_hash, "current510 fixture snapshot", prior_bytes)
            snapshot_bytes += prior_bytes
        else:
            _same(snapshot, "", "current510 unused fixture snapshot")
    if seen != set(expected):
        raise RuntimeBenchmarkAnalysisError("current510 custody fixture identities differ")
    journal_path = Path(str(path.parent / "fixture-custody.json"))
    try:
        journal_bytes = _read_bounded(journal_path, 1024 * 1024, "current510 custody journal")
        journal = json.loads(journal_bytes.decode("utf-8"), object_pairs_hook=_reject_duplicate_object, parse_constant=_reject_nonfinite_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("current510 custody journal differs") from error
    expected_journal = [{**row, "restoration_status": "pending", "restored_sha256": "", "restored_bytes": 0} for row in fixtures]
    _same_json(journal, expected_journal, "current510 custody journal")
    pre_sample_bytes = snapshot_bytes + len(journal_bytes)
    expected_reserve = (2 * pre_sample_bytes + 1024 * 1024 - 1) // (1024 * 1024) + 1
    _same(reserve, expected_reserve, "current510 custody calculated reserve")
    result_bytes = _read_bounded(Path(str(path)), 1024 * 1024, "current510 custody result bytes")
    if pre_sample_bytes + len(result_bytes) > reserve * 1024 * 1024:
        raise RuntimeBenchmarkAnalysisError("current510 custody output exceeds reserved budget")
    physical = _mapping(sample.get("physical_markers"), "current510 physical markers")
    log = _verified_file(physical.get("fixture_log"), physical.get("fixture_log_sha256"), "current510 scheduled fixture log")
    _verified_file(physical.get("stdout"), physical.get("stdout_sha256"), "current510 scheduled stdout")
    try:
        text = _read_bounded(log, 16 * 1024 * 1024, "current510 scheduled log").decode("utf-8")
        markers = [json.loads(value) for value in re.findall(r"\[MIR5_RUNTIME_ACTIVE\] (\{[^\r\n]+\})", text)]
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeBenchmarkAnalysisError("current510 scheduled marker log differs") from error
    if re.search(r"(?im)^\s*\d+[.]\d+\s+Error\b|^Error while running event\b|\bException at tick\b|\bnon-recoverable error\b|^stack traceback:$", text):
        raise RuntimeBenchmarkAnalysisError("current510 scheduled log contains fatal diagnostics")
    kind = "repair-stress" if schedule["scenario"] == "repair-active" else "agriculture-scale"
    for stage in ("start", "complete"):
        matches = [marker for marker in markers if marker.get("kind") == kind and marker.get("stage") == stage]
        if len(matches) != 1:
            raise RuntimeBenchmarkAnalysisError("current510 scheduled raw marker count differs")
        _same_json(matches[0], physical.get(stage), "current510 scheduled raw " + stage + " marker")


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
    identity: tuple[int, str] | None = None
    for entry in rows:
        row = _mapping(entry, "process memory row")
        _same(_string(row.get("phase"), "process memory phase"), "benchmark", "process memory phase")
        _same(_string(row.get("role"), "process memory role"), "factorio", "process memory role")
        current_identity = (
            _integer(row.get("pid"), "process memory PID", minimum=1),
            _string(row.get("start_utc"), "process memory start time"),
        )
        if identity is None:
            identity = current_identity
        elif identity != current_identity:
            raise RuntimeBenchmarkAnalysisError("process memory identity differs")
        working = _integer(row.get("working_set_bytes"), "process memory working bytes", minimum=0)
        private = _integer(row.get("private_bytes"), "process memory private bytes", minimum=0)
        maximum_working = max(maximum_working, working)
        maximum_private = max(maximum_private, private)
    _same(_integer(native.get("maximum_sampled_working_set_bytes"), "sampled working maximum", minimum=0), maximum_working, "sampled working maximum")
    _same(_integer(native.get("maximum_sampled_private_bytes"), "sampled private maximum", minimum=0), maximum_private, "sampled private maximum")


def _archive_closure(value: Any, label: str) -> dict[str, str]:
    archives = _mapping(value, label)
    closure: dict[str, str] = {}
    for leaf, digest in archives.items():
        name = _string(leaf, label + " leaf")
        if "/" in name or "\\" in name or name in closure:
            raise RuntimeBenchmarkAnalysisError(label + " leaf differs")
        closure[name] = _sha256(digest, label + " SHA-256")
    if not closure:
        raise RuntimeBenchmarkAnalysisError(label + " is empty")
    return closure


def _active_binding_contracts(capture_record: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Derive the producer's scheduled binding fields from pinned seed capture."""
    contracts: dict[str, dict[str, Any]] = {}
    for entry in _array(capture_record.get("captures"), "active binding captures"):
        row = _mapping(entry, "active binding capture")
        identifier = _string(row.get("id"), "active binding id")
        if identifier in contracts:
            raise RuntimeBenchmarkAnalysisError("active binding id duplicates")
        profile = _mapping(row.get("profile"), "active binding profile")
        selection = _mapping(profile.get("selection"), "active binding profile selection")
        archives = _archive_closure(selection.get("archive_sha256"), "active binding profile archives")
        for fixture in _array(row.get("fixtures"), "active binding fixtures"):
            fixture_row = _mapping(fixture, "active binding fixture")
            leaf = PureWindowsPath(_string(fixture_row.get("archive"), "active binding fixture archive")).name
            if not leaf:
                raise RuntimeBenchmarkAnalysisError("active binding fixture archive leaf differs")
            digest = _sha256(fixture_row.get("sha256"), "active binding fixture SHA-256")
            if leaf in archives and archives[leaf] != digest:
                raise RuntimeBenchmarkAnalysisError("active binding fixture archive conflicts")
            archives[leaf] = digest
        seed = _mapping(row.get("active_seed"), "active binding seed")
        contracts[identifier] = {
            "profile_sha256": _sha256(profile.get("sha256"), "active binding profile SHA-256"),
            "archives": archives,
            "seed_sha256": _sha256(seed.get("sha256"), "active binding seed SHA-256"),
            "seed_bytes": _integer(seed.get("bytes"), "active binding seed bytes", minimum=1),
        }
    expected_ids = {row["id"] for row in _active_rows()}
    if set(contracts) != expected_ids:
        raise RuntimeBenchmarkAnalysisError("active binding ids differ")
    return contracts


def _selected_closure(value: Any, label: str) -> list[tuple[str, str, bool, str]]:
    selected = _array(value, label)
    closure: list[tuple[str, str, bool, str]] = []
    identities: set[tuple[str, str]] = set()
    for entry in selected:
        row = _mapping(entry, label + " entry")
        identity = (_string(row.get("name"), label + " name"), _string(row.get("version"), label + " version"))
        if identity in identities:
            raise RuntimeBenchmarkAnalysisError(label + " identity duplicates")
        identities.add(identity)
        closure.append((*identity, _boolean(row.get("builtin"), label + " builtin"), _sha256(row.get("sha256"), label + " SHA-256")))
    if not closure:
        raise RuntimeBenchmarkAnalysisError(label + " is empty")
    return sorted(closure)


def _validate_physical_markers(value: Any, schedule: dict[str, Any], native: dict[str, Any], owned_seed_path: str) -> None:
    physical = _mapping(value, "physical markers")
    kind = "repair-stress" if schedule["scenario"] == "repair-active" else "agriculture-scale"
    start = _marker(physical.get("start"), "sample start marker", kind, "start", "pending")
    complete = _marker(physical.get("complete"), "sample complete marker", kind, "complete", "passed")
    owned_seed = PureWindowsPath(owned_seed_path)
    if not owned_seed.is_absolute() or ".." in owned_seed.parts or owned_seed.parts[-3:] != (schedule["id"], "input", "fresh-owned-active-seed.zip"):
        raise RuntimeBenchmarkAnalysisError("owned seed path is outside its scheduled sample")
    sample_root = owned_seed.parent.parent
    _same(PureWindowsPath(_string(physical.get("fixture_log"), "sample fixture log path")), sample_root / "write-data" / "factorio-current.log", "sample fixture log path")
    _sha256(physical.get("fixture_log_sha256"), "sample fixture log SHA-256")
    _same(_string(native.get("stdout"), "native stdout path"), "process-1.stdout.txt", "native stdout leaf")
    _same(PureWindowsPath(_string(physical.get("stdout"), "sample physical stdout path")), sample_root / "process-1.stdout.txt", "sample physical stdout path")
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
    pilot_native: dict[str, dict[str, Any]],
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
    archives = _archive_closure(row.get("archives"), "observation archives")
    selected_leaf = "more-infinite-research_4.7.21002.zip" if schedule["arm"] == "published" else CANDIDATE_LEAF
    selected_hash = PUBLISHED_SHA256 if schedule["arm"] == "published" else CANDIDATE_SHA256
    _expect_hash(archives.get(selected_leaf), selected_hash, "observation player archive SHA-256")
    seed = _mapping(row.get("seed"), "observation seed")
    _string(seed.get("source_path"), "seed source path")
    seed_hash = _sha256(seed.get("source_sha256"), "seed source SHA-256")
    capture_id = "repair-" + schedule["arm"] if schedule["scenario"] == "repair-active" else f"agriculture-{schedule['arm']}-{schedule['tier']}"
    expected_pilot = pilot_native[capture_id]
    if archives != _archive_closure(expected_pilot.get("archives"), "marker pilot archives"):
        raise RuntimeBenchmarkAnalysisError("observation archive closure differs")
    capture_seed = _mapping(captures[capture_id].get("active_seed"), "capture active seed")
    _expect_hash(seed_hash, capture_seed.get("sha256"), "seed source SHA-256")
    _string(seed.get("owned_path"), "owned seed path")
    _same(_string(seed.get("owned_leaf"), "owned seed leaf"), "fresh-owned-active-seed.zip", "owned seed leaf")
    _expect_hash(seed.get("owned_sha256"), seed_hash, "owned seed SHA-256")
    owned_bytes = _integer(seed.get("bytes"), "owned seed bytes", minimum=1)
    if KIND == _CURRENT510_BINDINGS["KIND"]:
        _same(_string(seed.get("source_path"), "current510 seed source path"), _string(capture_seed.get("path"), "current510 capture seed path"), "current510 seed source path")
        _same(owned_bytes, _integer(capture_seed.get("bytes"), "current510 capture seed bytes", minimum=1), "current510 owned seed bytes")
        _verified_file(seed.get("source_path"), seed_hash, "current510 sample source seed", owned_bytes)
        _verified_file(seed.get("owned_path"), seed_hash, "current510 sample owned seed", owned_bytes)
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
    _validate_physical_markers(row.get("physical_markers"), schedule, native, seed["owned_path"])
    restoration = _mapping(row.get("library_control_restoration"), "library control restoration")
    _same(_string(restoration.get("status"), "library restoration status"), "restored-direct-library-controls", "library restoration status")
    _expect_hash(restoration.get("profile_sha256"), expected_profile["sha256"], "library restoration profile SHA-256")
    for key in ("dependency_payload_bytes_copied", "archive_links_created", "archive_extractions"):
        _same(_integer(restoration.get(key), "library restoration " + key, minimum=0), 0, "library restoration " + key)
    expected_restoration = _mapping(expected_pilot.get("library_control_restoration"), "marker pilot library restoration")
    if _selected_closure(restoration.get("selected"), "library restoration selected archives") != _selected_closure(expected_restoration.get("selected"), "marker pilot selected archives"):
        raise RuntimeBenchmarkAnalysisError("library restoration selected closure differs")
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


def analyze(plan: dict[str, Any], plan_sha256: str, result: dict[str, Any], result_sha256: str, controller_source: Path | None = None) -> dict[str, Any]:
    contract = _validate_plan(plan, plan_sha256)
    if KIND != _CURRENT510_BINDINGS["KIND"]:
        frozen_capture, frozen_pilot = _frozen_active_prerequisites()
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
    if KIND == _CURRENT510_BINDINGS["KIND"]:
        _same(revision, _CURRENT510_CONTROLLER_REVISION, "current510 private controller revision")
        _expect_hash(raw_controller, _CURRENT510_CONTROLLER_SHA256, "current510 private controller raw Git")
        _verify_current510_controller_file(controller_source)
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
    if KIND == _CURRENT510_BINDINGS["KIND"]:
        _same(_string(helpers.get("stage_checkout_revision"), "current510 stage checkout"), PLAN_REVISION, "current510 stage checkout")
        captures, pilot_native, mixed = _validate_current510_mixed(result, contract["profiles"])
        provenance = _validate_current510_provenance(result.get("row_provenance"), captures, contract["profiles"])
        prerequisite_summary = {side: {name: {"path": reference["path"], "sha256": reference["sha256"]}
                               for name, reference in values.items() if name in ("capture", "pilot", "origins")}
                                for side, values in mixed.items()}
        prerequisite_summary["published"]["plan"] = {"sha256": _CURRENT505_GROUND_BINDINGS["PLAN_SHA256"], "revision": _CURRENT505_GROUND_BINDINGS["PLAN_REVISION"], "source_reference": _CURRENT505_GROUND_BINDINGS["PLAN_SOURCE"]}
        prerequisite_summary["candidate"]["source_references"] = {row_id: provenance[row_id]["source_harness"] for row_id in provenance if provenance[row_id]["origin_kind"] == "current510-original-candidate"}
    else:
        capture_reference = _mapping(result.get("active_seed_capture"), "active seed capture reference")
        pilot_reference = _mapping(result.get("unscored_marker_pilot"), "marker pilot reference")
        captures = _validate_capture_reference(capture_reference, plan_sha256, contract["profiles"], frozen_capture)
        pilot_native = _validate_pilot_reference(pilot_reference, plan_sha256, capture_reference, captures, frozen_pilot)
        prerequisite_summary = {
            "active_seed_capture": {key: capture_reference[key] for key in ("path", "sha256", "kind", "status")},
            "marker_pilot": {key: pilot_reference[key] for key in ("path", "sha256", "kind", "status")},
        }
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
        if KIND == _CURRENT510_BINDINGS["KIND"]:
            capture_id = ("repair-" + schedule["arm"] if schedule["scenario"] == "repair-active" else
                          f"agriculture-{schedule['arm']}-{schedule['tier']}")
            _same_json(by_id[schedule["id"]].get("input_provenance"), provenance[capture_id], "current510 observation provenance")
            _validate_current510_custody(by_id[schedule["id"]], schedule, provenance[capture_id])
        metrics = _validate_sample(by_id[schedule["id"]], schedule, contract["profiles"], captures, pilot_native)
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
        "status": ANALYSIS_STATUS,
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
        "active_prerequisites": prerequisite_summary,
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
    parser.add_argument("--cohort", choices=("r06", "current38c", "current505-ground", "current510-mixed"), default="r06")
    parser.add_argument("--raw-plan", required=True, type=Path)
    parser.add_argument("--expected-plan-sha256", required=True)
    parser.add_argument("--controller-source", type=Path, help="retained raw controller body (required for current510-mixed)")
    parser.add_argument("--result", required=True, type=Path)
    parser.add_argument("--expected-result-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(sys.argv[1:] if argv is None else argv)
    try:
        select_cohort(arguments.cohort)
        if KIND == _CURRENT510_BINDINGS["KIND"]:
            _verify_current510_controller_file(arguments.controller_source)
        expected_plan_sha256 = _sha256(arguments.expected_plan_sha256, "expected plan SHA-256")
        expected_result_sha256 = _sha256(arguments.expected_result_sha256, "expected result SHA-256")
        _expect_hash(expected_plan_sha256, PLAN_SHA256, "expected R06 plan SHA-256")
        plan, plan_sha256 = _read_json(arguments.raw_plan, MAX_PLAN_BYTES, "raw plan")
        result, result_sha256 = _read_json(arguments.result, MAX_RESULT_BYTES, "raw result")
        _expect_hash(plan_sha256, expected_plan_sha256, "raw plan SHA-256")
        _expect_hash(result_sha256, expected_result_sha256, "raw result SHA-256")
        _validate_prepared_inputs_sidecar(arguments.result, result)
        _write_output(arguments.output, analyze(plan, plan_sha256, result, result_sha256, arguments.controller_source))
    except RuntimeBenchmarkAnalysisError as error:
        print(f"[mir5-runtime-benchmark-analysis-refused] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
