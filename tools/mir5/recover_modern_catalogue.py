"""Recover and check the complete published MIR 4.7 modern catalogue.

This package-excluded tool consumes only hash-verified Factorio data-stage
captures.  It records the full published additions and patches for the fixed
F210 Base and Space Age profiles, then compares a later candidate capture
against the independent no-MIR baseline plus that explicit intended output.
It does not execute Factorio, construct player output, or provide a runtime
catalogue.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
from typing import Any, Mapping

import replay


class CatalogueError(ValueError):
    """A capture, oracle, or candidate does not meet this narrow contract."""


SCHEMA = 1
KIND = "MIR5ModernF210PublishedCatalogueV1"
REVIEW_KIND = "MIR5ModernCatalogueReviewedDifferencesV1"
PRIVATE_MOD_DATA_PREFIX = "more-infinite-research-"
MAXIMUM_LEVEL_POLICY = "more-infinite-research-maximum-level-policy"


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CatalogueError(f"{label} is not valid UTF-8 JSON: {path}") from error


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or not all(isinstance(key, str) for key in value):
        raise CatalogueError(f"{label} must be a JSON object with string keys")
    return value


def _list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise CatalogueError(f"{label} must be a JSON array")
    return value


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _safe_relative(root: Path, relative: Any, label: str) -> Path:
    if not isinstance(relative, str) or not relative:
        raise CatalogueError(f"{label} lacks a relative path")
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise CatalogueError(f"{label} has an unsafe capture-relative path: {relative!r}")
    resolved_root = root.resolve()
    resolved = (root / candidate).resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise CatalogueError(f"{label} escapes its capture root")
    return resolved


def _recorded_file(root: Path, value: Any, label: str, *, require_bytes: bool = True) -> tuple[Path, dict[str, Any]]:
    record = _mapping(value, label)
    digest = record.get("sha256")
    if not isinstance(digest, str) or len(digest) != 64 or any(char not in "0123456789abcdefABCDEF" for char in digest):
        raise CatalogueError(f"{label} lacks a valid SHA-256")
    path = _safe_relative(root, record.get("path"), label)
    if not path.is_file():
        raise CatalogueError(f"{label} is absent: {record.get('path')}")
    actual = _sha256(path)
    if actual != digest.upper():
        raise CatalogueError(f"{label} hash differs from its raw capture receipt")
    expected_bytes = record.get("bytes")
    if require_bytes and (not isinstance(expected_bytes, int) or expected_bytes < 0
                          or path.stat().st_size != expected_bytes):
        raise CatalogueError(f"{label} byte count differs from its raw capture receipt")
    if not require_bytes and expected_bytes is not None and (
            not isinstance(expected_bytes, int) or expected_bytes < 0
            or path.stat().st_size != expected_bytes):
        raise CatalogueError(f"{label} byte count differs from its capture receipt")
    return path, {
        "path": str(Path(record["path"])).replace("\\", "/"),
        "sha256": actual,
        "bytes": path.stat().st_size,
    }


def _normalise_mods(rows: Any, label: str, without_mir: bool) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for index, raw in enumerate(_list(rows, label), 1):
        row = _mapping(raw, f"{label}[{index}]")
        name, version = row.get("name"), row.get("version")
        if not isinstance(name, str) or not name or not isinstance(version, str) or not version:
            raise CatalogueError(f"{label}[{index}] lacks name/version")
        if without_mir and name == "more-infinite-research":
            continue
        normal: dict[str, Any] = {"name": name, "version": version}
        for field in ("enabled", "builtin"):
            if field in row:
                if not isinstance(row[field], bool):
                    raise CatalogueError(f"{label}[{index}].{field} must be boolean")
                normal[field] = row[field]
        if "sha256" in row:
            digest = row["sha256"]
            if (not isinstance(digest, str) or len(digest) != 64
                    or any(char not in "0123456789abcdefABCDEF" for char in digest)):
                raise CatalogueError(f"{label}[{index}].sha256 is invalid")
            normal["sha256"] = digest.upper()
        output.append(normal)
    return output


def _loaded_without_mir(value: Any, label: str) -> list[str]:
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not all(isinstance(entry, str) and entry for entry in value):
        raise CatalogueError(f"{label} is invalid")
    return [entry for entry in value if not entry.startswith("more-infinite-research@")] 


def read_capture(root: Path, *, require_mir: bool | None) -> dict[str, Any]:
    """Read a data-stage receipt while verifying its raw JSON dumps first."""
    root = root.resolve()
    result_path = root / "result.json"
    if not root.is_dir() or not result_path.is_file():
        raise CatalogueError(f"capture result is absent: {result_path}")
    result = _mapping(_load_json(result_path, "capture result"), "capture result")
    process = _mapping(result.get("process"), "capture process")
    if (result.get("status") != "completed-data-stage-observation-only"
            or process.get("passed") is not True or process.get("timed_out") is not False
            or process.get("exit_code") != 0):
        raise CatalogueError("capture did not complete as a natural zero-exit data-stage observation")
    generated = _mapping(result.get("generated_selection"), "capture generated selection")
    selection_path, selection_file = _recorded_file(root, generated, "generated selection", require_bytes=False)
    selection = _mapping(_load_json(selection_path, "generated selection"), "generated selection")
    selection_rows = _normalise_mods(selection.get("mods"), "generated selection mods", without_mir=False)
    recorded_rows = _normalise_mods(generated.get("mods"), "recorded selection mods", without_mir=False)
    if selection_rows != recorded_rows:
        raise CatalogueError("selection.json differs from the raw capture receipt")
    contains_mir = any(row["name"] == "more-infinite-research" for row in selection_rows)
    if require_mir is not None and contains_mir != require_mir:
        expected = "must" if require_mir else "must not"
        raise CatalogueError(f"capture {expected} select more-infinite-research")

    dumps = _mapping(result.get("dumps"), "capture dumps")
    raw_path, raw_file = _recorded_file(root, dumps.get("data_raw"), "data-raw dump")
    settings_path, settings_file = _recorded_file(root, dumps.get("mod_settings"), "mod-settings dump")
    raw = _mapping(_load_json(raw_path, "data-raw dump"), "data-raw dump")
    settings = _mapping(_load_json(settings_path, "mod-settings dump"), "mod-settings dump")
    try:
        replay._validate_raw(raw, "data-raw dump")
        replay._validate_raw(settings, "mod-settings dump")
    except replay.ReplayError as error:
        raise CatalogueError(str(error)) from error

    engine = _mapping(result.get("engine"), "capture engine")
    engine_identity = {field: engine.get(field) for field in ("sha256", "base_version", "factorio_version")}
    if not all(isinstance(value, str) and value for value in engine_identity.values()):
        raise CatalogueError("capture engine lacks exact identity")
    engine_identity["sha256"] = engine_identity["sha256"].upper()
    selected = _normalise_mods(result.get("selected_archives"), "selected archives", without_mir=True)
    selected_all = _normalise_mods(result.get("selected_archives"), "selected archives", without_mir=False)
    mir_records = [row for row in selected_all if row["name"] == "more-infinite-research"]
    mir_archive = result.get("mir_archive")
    if require_mir:
        archive = _mapping(mir_archive, "published MIR archive")
        archive_name, archive_version, archive_hash = archive.get("name"), archive.get("version"), archive.get("sha256")
        if (archive_name != "more-infinite-research" or not isinstance(archive_version, str) or not archive_version
                or not isinstance(archive_hash, str) or len(archive_hash) != 64
                or any(char not in "0123456789abcdefABCDEF" for char in archive_hash)):
            raise CatalogueError("published MIR archive lacks its exact receipt identity")
        if len(mir_records) != 1 or mir_records[0].get("version") != archive_version or mir_records[0].get("sha256") != archive_hash.upper():
            raise CatalogueError("published MIR archive differs from the selected archive receipt")
    elif require_mir is False and (mir_archive is not None or mir_records):
        raise CatalogueError("no-MIR capture unexpectedly records MIR")
    selection_without_mir = _normalise_mods(selection.get("mods"), "generated selection mods", without_mir=True)
    loaded = _loaded_without_mir(result.get("loaded_selection"), "capture loaded selection")
    profile = _mapping(result.get("profile_input"), "capture profile input")
    profile_hash = profile.get("sha256")
    if not isinstance(profile_hash, str) or len(profile_hash) != 64:
        raise CatalogueError("capture profile input lacks a SHA-256")
    return {
        "root": root,
        "raw": raw,
        "settings": settings,
        "engine": engine_identity,
        "selection": selection_without_mir,
        "selected": selected,
        "loaded": loaded,
        "profile": {"path": profile.get("path"), "sha256": profile_hash.upper()},
        "contains_mir": contains_mir,
        "files": {
            "result": {"path": "result.json", "sha256": _sha256(result_path), "bytes": result_path.stat().st_size},
            "selection": selection_file,
            "data_raw": raw_file,
            "mod_settings": settings_file,
        },
        "published_mir": mir_archive,
    }


def _assert_matching_inputs(before: Mapping[str, Any], after: Mapping[str, Any]) -> None:
    for field, message in (
        ("engine", "capture engines differ"),
        ("selection", "generated upstream selections differ after removing MIR"),
        ("selected", "selected upstream archive identities differ after removing MIR"),
        ("loaded", "loaded upstream selections differ after removing MIR"),
        ("profile", "profile input receipts differ"),
    ):
        if before[field] != after[field]:
            raise CatalogueError(message)


def _same(left: Any, right: Any) -> bool:
    return replay._same_json_value(left, right)


def _changed_paths(before: Any, after: Any) -> list[str]:
    return [".".join(path) or "<entire-row>" for path, _ in replay._changed_fields(before, after)]


def _row_records(diff: Mapping[str, Any], before: Mapping[str, Any]) -> dict[str, list[dict[str, Any]]]:
    additions = [
        {"type": prototype_type, "name": name, "row": row}
        for prototype_type, name, row in diff["additions"]
    ]
    patches = [
        {
            "type": prototype_type,
            "name": name,
            "before": before[prototype_type][name],
            "after": _apply_changes(before[prototype_type][name], changes),
            "changed_paths": [".".join(path) or "<entire-row>" for path, _ in changes],
        }
        for prototype_type, name, changes in diff["patches"]
    ]
    return {"additions": additions, "patches": patches}


def _apply_changes(before: Any, changes: list[tuple[tuple[str, ...], Any]]) -> Any:
    target = deepcopy(before)
    for path, value in changes:
        if not path:
            raise CatalogueError("whole-row replacement is not a supported native patch")
        cursor = target
        for part in path[:-1]:
            if not isinstance(cursor, dict):
                raise CatalogueError("native patch path does not address an object field")
            if part not in cursor or not isinstance(cursor[part], dict):
                cursor[part] = {}
            cursor = cursor[part]
        if not isinstance(cursor, dict):
            raise CatalogueError("native patch path does not address an object field")
        if value is None:
            cursor.pop(path[-1], None)
        else:
            cursor[path[-1]] = value
    return target


def _diff_domain(before: Mapping[str, Any], after: Mapping[str, Any], label: str) -> dict[str, list[dict[str, Any]]]:
    try:
        diff = replay._diff_prototypes(before, after, label)
    except replay.ReplayError as error:
        raise CatalogueError(str(error)) from error
    return _row_records(diff, before)


def _technology_group(row: Mapping[str, Any]) -> str:
    name = str(row["name"])
    effects = row.get("effects", [])
    effect_types = {effect.get("type") for effect in effects if isinstance(effect, Mapping)}
    if not name.startswith("recipe-prod-research_"):
        return "native-continuations"
    if effect_types == {"change-recipe-productivity"}:
        return "recipe-productivity"
    if effect_types == {"nothing"}:
        return "scripted-runtime-carriers"
    return "native-modifier-research"


def _technology_facts(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    facts: list[dict[str, Any]] = []
    for record in records:
        if record["type"] != "technology":
            continue
        row = record["row"]
        unit = row.get("unit", {})
        facts.append({
            "name": record["name"],
            "group": _technology_group(row),
            "max_level": row.get("max_level"),
            "enabled": row.get("enabled"),
            "hidden": row.get("hidden"),
            "prerequisites": row.get("prerequisites", []),
            "science": unit.get("ingredients", []),
            "count": unit.get("count"),
            "count_formula": unit.get("count_formula"),
            "time": unit.get("time"),
            "effects": row.get("effects", []),
        })
    return facts


def _normal_patterns(data: Mapping[str, list[dict[str, Any]]], settings: Mapping[str, list[dict[str, Any]]]) -> dict[str, Any]:
    technology = [record for record in data["additions"] if record["type"] == "technology"]
    groups: dict[str, list[str]] = {}
    for record in technology:
        groups.setdefault(_technology_group(record["row"]), []).append(record["name"])
    setting_groups = {"ips-family-descriptors": [], "mir-control-descriptors": [], "other-descriptors": []}
    for record in settings["additions"]:
        name = record["name"]
        key = "ips-family-descriptors" if name.startswith("ips-") else (
            "mir-control-descriptors" if name.startswith("mir-") else "other-descriptors")
        setting_groups[key].append(name)
    return {
        "technology": [{"group": key, "count": len(sorted(names)), "names": sorted(names)}
                       for key, names in sorted(groups.items())],
        "settings": [{"group": key, "count": len(sorted(names)), "names": sorted(names)}
                     for key, names in sorted(setting_groups.items()) if names],
    }


def _private_metadata(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    private: list[dict[str, Any]] = []
    for record in records:
        if record["type"] == "mod-data" and record["name"].startswith(PRIVATE_MOD_DATA_PREFIX):
            private.append({
                "type": record["type"],
                "name": record["name"],
                "disposition": "captured-private-mir4-architecture-not-required-player-output",
                "review_status": "explicit-cutover-disposition",
            })
    return private


def _intended_data(records: Mapping[str, list[dict[str, Any]]]) -> dict[str, Any]:
    private_names = _private_metadata(records["additions"])
    return {
        "from_published_output": True,
        "exclude_published_additions": private_names,
    }


def _captured_maximum_level_bindings(raw: Mapping[str, Any]) -> dict[str, Any]:
    """Keep the compact policy tuples as evidence, never as player input."""
    mod_data = _mapping(raw.get("mod-data"), "published mod-data")
    record = _mapping(mod_data.get(MAXIMUM_LEVEL_POLICY), "published maximum-level policy")
    if record.get("type") != "mod-data" or record.get("name") != MAXIMUM_LEVEL_POLICY:
        raise CatalogueError("published maximum-level policy has the wrong identity")
    data = _mapping(record.get("data"), "published maximum-level policy data")
    bindings: list[dict[str, Any]] = []
    for raw_binding in _list(data.get("bindings"), "published maximum-level bindings"):
        binding = _mapping(raw_binding, "published maximum-level binding")
        technology, setting, source, operation = (
            binding.get("technology"), binding.get("setting_name"), binding.get("source"), binding.get("operation"))
        semantic = _mapping(binding.get("semantic"), "published maximum-level semantic")
        provenance = _mapping(binding.get("provenance"), "published maximum-level provenance")
        if (not all(isinstance(value, str) and value for value in (technology, setting, source, operation))
                or not isinstance(semantic.get("family_id"), str) or not isinstance(semantic.get("stream_id"), str)
                or not isinstance(provenance.get("manifest_id"), str)):
            raise CatalogueError("published maximum-level binding is incomplete")
        native_owner = technology if source == "native-owner" and operation == "preserve_native_owner" else None
        bindings.append({
            "technology": technology,
            "setting": setting,
            "source": source,
            "operation": operation,
            "native_owner_identity": native_owner,
            "family_id": semantic["family_id"],
            "stream_id": semantic["stream_id"],
            "manifest_id": provenance["manifest_id"],
        })
    if len({row["technology"] for row in bindings}) != len(bindings):
        raise CatalogueError("published maximum-level bindings duplicate a technology")
    return {
        "type": "mod-data",
        "name": MAXIMUM_LEVEL_POLICY,
        "data_type": record.get("data_type"),
        "schema": data.get("schema"),
        "disposition": "captured-private-mir4-architecture-not-required-player-output",
        "review_status": "explicit-cutover-disposition",
        "bindings": bindings,
    }


def _capture_receipt(capture: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "engine": capture["engine"],
        "selection_without_mir": capture["selection"],
        "selected_archives_without_mir": capture["selected"],
        "loaded_without_mir": capture["loaded"],
        "profile_input": capture["profile"],
        "files": capture["files"],
    }


def recover_profile(identifier: str, no_mir_root: Path, published_root: Path) -> dict[str, Any]:
    no_mir = read_capture(no_mir_root, require_mir=False)
    published = read_capture(published_root, require_mir=True)
    _assert_matching_inputs(no_mir, published)
    data = _diff_domain(no_mir["raw"], published["raw"], f"{identifier} data")
    settings = _diff_domain(no_mir["settings"], published["settings"], f"{identifier} settings")
    private = _private_metadata(data["additions"])
    generated = [record for record in data["additions"] if record["type"] == "technology"]
    special = {
        "native_continuations": [record for record in generated
                                 if _technology_group(record["row"]) == "native-continuations"],
        "foreign_prototype_patches": data["patches"],
        "published_private_mir4_metadata": private,
    }
    return {
        "id": identifier,
        "capture_receipts": {"no_mir": _capture_receipt(no_mir), "published_470": _capture_receipt(published)},
        "published_output": {"data": data, "settings": settings},
        "intended_player_output": {
            "data": _intended_data(data),
            "settings": {"from_published_output": True},
        },
        "normal_patterns": _normal_patterns(data, settings),
        "special_cases": special,
        "technology_owner_progression_facts": _technology_facts(generated),
        "captured_maximum_level_bindings": _captured_maximum_level_bindings(published["raw"]),
    }


def recover_inventory(base_no_mir: Path, base_published: Path,
                      space_age_no_mir: Path, space_age_published: Path) -> dict[str, Any]:
    profiles = [
        recover_profile("base-f210", base_no_mir, base_published),
        recover_profile("space-age-f210", space_age_no_mir, space_age_published),
    ]
    return {
        "schema": SCHEMA,
        "kind": KIND,
        "status": "hash-verified-published-modern-catalogue-oracle",
        "claims": {
            "native_qualification": False,
            "player_package": False,
            "runtime_catalogue": False,
            "candidate_expectations_derived_from_candidate": False,
        },
        "source": {
            "published_version": "4.7.21000",
            "engine_family": "2.1",
            "profiles": [profile["id"] for profile in profiles],
        },
        "profiles": profiles,
        "reviewed_differences_contract": {
            "kind": REVIEW_KIND,
            "required_fields": ["id", "profile", "domain", "type", "name", "expected_candidate", "reason"],
            "rule": "Only an exact named entry can change the independent intended output; omissions are null.",
        },
    }


def _write_new_json(path: Path, value: Any) -> None:
    if path.exists():
        raise CatalogueError(f"preserve existing output: {path}")
    if not path.parent.is_dir():
        raise CatalogueError(f"output parent is absent: {path.parent}")
    path.write_bytes(_json_bytes(value))


def _inventory_profile(inventory: Mapping[str, Any], identifier: str) -> Mapping[str, Any]:
    if inventory.get("schema") != SCHEMA or inventory.get("kind") != KIND:
        raise CatalogueError("inventory has an unsupported schema or kind")
    rows = _list(inventory.get("profiles"), "inventory profiles")
    matches = [row for row in rows if isinstance(row, Mapping) and row.get("id") == identifier]
    if len(matches) != 1:
        raise CatalogueError(f"inventory has no unique profile: {identifier}")
    return _mapping(matches[0], f"inventory profile {identifier}")


def _overlay_domain(baseline: Mapping[str, Any], expected: Mapping[str, Any], label: str) -> dict[str, Any]:
    result = deepcopy(baseline)
    for addition in _list(expected.get("additions"), f"{label} additions"):
        row = _mapping(addition, f"{label} addition")
        prototype_type, name, value = row.get("type"), row.get("name"), row.get("row")
        if not isinstance(prototype_type, str) or not isinstance(name, str) or not isinstance(value, Mapping):
            raise CatalogueError(f"{label} addition is malformed")
        bucket = result.setdefault(prototype_type, {})
        if name in bucket:
            raise CatalogueError(f"{label} addition collides with baseline: {prototype_type}.{name}")
        bucket[name] = deepcopy(value)
    for patch in _list(expected.get("patches"), f"{label} patches"):
        row = _mapping(patch, f"{label} patch")
        prototype_type, name = row.get("type"), row.get("name")
        if not isinstance(prototype_type, str) or not isinstance(name, str):
            raise CatalogueError(f"{label} patch is malformed")
        bucket = result.get(prototype_type)
        if not isinstance(bucket, dict) or name not in bucket:
            raise CatalogueError(f"{label} patch target is absent from baseline: {prototype_type}.{name}")
        if not _same(bucket[name], row.get("before")):
            raise CatalogueError(f"{label} patch baseline differs: {prototype_type}.{name}")
        after = row.get("after")
        if not isinstance(after, Mapping):
            raise CatalogueError(f"{label} patch lacks an exact after row")
        bucket[name] = deepcopy(after)
    return result


def _intended_domain(profile: Mapping[str, Any], domain: str) -> Mapping[str, Any]:
    published = _mapping(profile.get("published_output"), "published output")
    intended = _mapping(profile.get("intended_player_output"), "intended player output")
    source = _mapping(published.get(domain), f"published {domain}")
    instruction = _mapping(intended.get(domain), f"intended {domain}")
    if instruction.get("from_published_output") is not True:
        raise CatalogueError(f"intended {domain} must explicitly derive from published output")
    output = deepcopy(source)
    exclusions = _list(instruction.get("exclude_published_additions", []), f"intended {domain} exclusions")
    names: set[tuple[str, str]] = set()
    for raw in exclusions:
        row = _mapping(raw, f"intended {domain} exclusion")
        prototype_type, name = row.get("type"), row.get("name")
        if (not isinstance(prototype_type, str) or not prototype_type
                or not isinstance(name, str) or not name
                or row.get("disposition") != "captured-private-mir4-architecture-not-required-player-output"
                or row.get("review_status") != "explicit-cutover-disposition"):
            raise CatalogueError(f"intended {domain} exclusion lacks its cutover disposition")
        key = (prototype_type, name)
        if key in names:
            raise CatalogueError(f"intended {domain} exclusions duplicate an output")
        names.add(key)
    output["additions"] = [
        row for row in _list(output.get("additions"), f"published {domain} additions")
        if (row.get("type"), row.get("name")) not in names
    ]
    if len(output["additions"]) + len(names) != len(_list(source.get("additions"), f"published {domain} additions")):
        raise CatalogueError(f"intended {domain} excludes output absent from the published capture")
    return output


def _reviewed_differences(path: Path | None, profile: str) -> list[Mapping[str, Any]]:
    if path is None:
        return []
    document = _mapping(_load_json(path, "reviewed differences"), "reviewed differences")
    if document.get("schema") != SCHEMA or document.get("kind") != REVIEW_KIND:
        raise CatalogueError("reviewed differences have an unsupported schema or kind")
    output: list[Mapping[str, Any]] = []
    for raw in _list(document.get("differences"), "reviewed differences"):
        row = _mapping(raw, "reviewed difference")
        required = ("id", "profile", "domain", "type", "name", "expected_candidate", "reason")
        if any(field not in row for field in required):
            raise CatalogueError("reviewed difference lacks an exact disposition")
        if row["profile"] != profile:
            continue
        if (not isinstance(row["id"], str) or not row["id"] or row["domain"] not in {"data", "settings"}
                or not isinstance(row["type"], str) or not row["type"]
                or not isinstance(row["name"], str) or not row["name"]
                or not isinstance(row["reason"], str) or not row["reason"]):
            raise CatalogueError("reviewed difference is malformed")
        output.append(row)
    seen = {(row["domain"], row["type"], row["name"]) for row in output}
    if len(seen) != len(output):
        raise CatalogueError("reviewed differences duplicate a named output")
    return output


def _apply_reviewed(expected: dict[str, Any], rows: list[Mapping[str, Any]], domain: str) -> None:
    for row in rows:
        if row["domain"] != domain:
            continue
        bucket = expected.setdefault(row["type"], {})
        value = row["expected_candidate"]
        if value is None:
            bucket.pop(row["name"], None)
            if not bucket:
                expected.pop(row["type"], None)
        else:
            if not isinstance(value, Mapping):
                raise CatalogueError("reviewed replacement must be a complete prototype/settings descriptor or null")
            expected.setdefault(row["type"], {})[row["name"]] = deepcopy(value)


def _difference_summary(expected: Mapping[str, Any], actual: Mapping[str, Any], domain: str) -> list[dict[str, Any]]:
    differences: list[dict[str, Any]] = []
    for prototype_type in sorted(set(expected) | set(actual), key=replay._sort_key):
        before = expected.get(prototype_type, {})
        after = actual.get(prototype_type, {})
        if not isinstance(before, Mapping) or not isinstance(after, Mapping):
            differences.append({"domain": domain, "type": prototype_type, "names": ["<non-object-domain>"]})
            continue
        names = [name for name in sorted(set(before) | set(after), key=replay._sort_key)
                 if name not in before or name not in after or not _same(before[name], after[name])]
        if names:
            differences.append({"domain": domain, "type": prototype_type, "names": names})
    return differences


def compare_candidate(inventory_path: Path, profile_id: str, baseline_root: Path,
                      candidate_root: Path, reviewed_path: Path | None = None) -> dict[str, Any]:
    inventory = _mapping(_load_json(inventory_path, "modern catalogue inventory"), "modern catalogue inventory")
    profile = _inventory_profile(inventory, profile_id)
    baseline = read_capture(baseline_root, require_mir=False)
    candidate = read_capture(candidate_root, require_mir=True)
    required_receipt = _mapping(_mapping(profile.get("capture_receipts"), "profile receipts").get("no_mir"), "no-MIR receipt")
    if _capture_receipt(baseline) != required_receipt:
        raise CatalogueError("candidate baseline does not match the inventory's independent no-MIR receipt")
    _assert_matching_inputs(baseline, candidate)
    expected_data = _overlay_domain(baseline["raw"], _intended_domain(profile, "data"), "data")
    expected_settings = _overlay_domain(baseline["settings"], _intended_domain(profile, "settings"), "settings")
    reviewed = _reviewed_differences(reviewed_path, profile_id)
    _apply_reviewed(expected_data, reviewed, "data")
    _apply_reviewed(expected_settings, reviewed, "settings")
    differences = (_difference_summary(expected_data, candidate["raw"], "data")
                   + _difference_summary(expected_settings, candidate["settings"], "settings"))
    return {
        "schema": SCHEMA,
        "kind": "MIR5ModernF210CandidateComparisonV1",
        "status": "equal-intended-native-output" if not differences else "different-intended-native-output",
        "scope": "complete data/settings output only; no gameplay, menu, save, runtime, or release qualification",
        "profile": profile_id,
        "inventory_sha256": _sha256(inventory_path),
        "baseline_receipt": baseline["files"],
        "candidate_receipt": candidate["files"],
        "reviewed_differences": [row["id"] for row in reviewed],
        "differences": differences,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    recover = commands.add_parser("recover", help="recover the fixed Base and Space Age oracle")
    recover.add_argument("--base-no-mir", type=Path, required=True)
    recover.add_argument("--base-published", type=Path, required=True)
    recover.add_argument("--space-age-no-mir", type=Path, required=True)
    recover.add_argument("--space-age-published", type=Path, required=True)
    recover.add_argument("--output", type=Path, required=True)
    compare = commands.add_parser("compare", help="compare a candidate capture with the independent oracle")
    compare.add_argument("--inventory", type=Path, required=True)
    compare.add_argument("--profile", choices=("base-f210", "space-age-f210"), required=True)
    compare.add_argument("--baseline", type=Path, required=True)
    compare.add_argument("--candidate", type=Path, required=True)
    compare.add_argument("--reviewed-differences", type=Path)
    compare.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "recover":
            result = recover_inventory(args.base_no_mir, args.base_published,
                                       args.space_age_no_mir, args.space_age_published)
            _write_new_json(args.output, result)
            print(json.dumps({"status": result["status"], "output": str(args.output.resolve())}, sort_keys=True))
            return 0
        result = compare_candidate(args.inventory, args.profile, args.baseline, args.candidate,
                                   args.reviewed_differences)
        if args.output is not None:
            _write_new_json(args.output, result)
        print(json.dumps(result, sort_keys=True))
        return 0 if not result["differences"] else 1
    except (CatalogueError, OSError, ValueError) as error:
        print(f"[mir5-modern-catalogue] {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
