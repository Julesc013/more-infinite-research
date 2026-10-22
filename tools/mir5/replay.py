"""Build a profile-specific offline diagnostic replay from two native captures.

This tool compares a completed no-MIR data-stage capture with a completed
published MIR 4.7 capture.  It writes plain data/settings-stage Lua and
comparison custody records.  It does not run Factorio, package a mod, or
participate in MIR 5 player construction.
"""
from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
import hashlib
import json
import math
from pathlib import Path
import shutil
import sys
from typing import Any


class ReplayError(ValueError):
    """The supplied capture pair cannot support an exact diagnostic replay."""


SETTING_SUFFIX = "-setting"
EMPTY_ENTRYPOINTS = (
    "data.lua",
    "data-updates.lua",
    "settings-updates.lua",
    "settings-final-fixes.lua",
)
DATA_OUTPUT = "data-final-fixes.lua"
SETTINGS_OUTPUT = "settings.lua"
RECEIPT_OUTPUT = "comparison-receipt.json"
INVENTORY_OUTPUT = "hash-inventory.json"
MAX_LUA_NUMBER = 1.7976931348623157e308
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def _safe_path(root: Path, relative: str, label: str) -> Path:
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts:
        raise ReplayError(f"{label} has an unsafe capture-relative path: {relative!r}")
    resolved_root = root.resolve()
    resolved = (root / path).resolve()
    if resolved_root != resolved and resolved_root not in resolved.parents:
        raise ReplayError(f"{label} escapes the capture root")
    return resolved


def _expect_mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ReplayError(f"{label} must be a JSON object")
    if not all(isinstance(key, str) for key in value):
        raise ReplayError(f"{label} contains a non-string key")
    return value


def _expect_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ReplayError(f"{label} must be a JSON array")
    return value


def _recorded_file(capture_root: Path, value: Any, label: str) -> tuple[Path, dict[str, Any]]:
    record = _expect_mapping(value, label)
    relative = record.get("path")
    digest = record.get("sha256")
    if not isinstance(relative, str) or not isinstance(digest, str) or len(digest) != 64:
        raise ReplayError(f"{label} lacks a path and SHA-256")
    if any(character not in "0123456789abcdefABCDEF" for character in digest):
        raise ReplayError(f"{label} has an invalid SHA-256")
    path = _safe_path(capture_root, relative, label)
    if not path.is_file():
        raise ReplayError(f"{label} is absent: {relative}")
    actual = _sha256(path)
    if actual != digest.upper():
        raise ReplayError(f"{label} hash differs from its capture record")
    expected_size = record.get("bytes")
    if expected_size is not None and (not isinstance(expected_size, int) or expected_size < 0 or path.stat().st_size != expected_size):
        raise ReplayError(f"{label} byte count differs from its capture record")
    return path, {"path": relative.replace("\\", "/"), "sha256": actual, "bytes": path.stat().st_size}


def _external_record(value: Any, label: str) -> dict[str, Any]:
    """Verify an input selected by the native capture, outside its output root."""
    record = _expect_mapping(value, label)
    recorded_path = record.get("path")
    digest = record.get("sha256")
    if not isinstance(recorded_path, str) or not recorded_path or not isinstance(digest, str) or len(digest) != 64:
        raise ReplayError(f"{label} lacks a path and SHA-256")
    path = Path(recorded_path)
    if not path.is_absolute():
        path = REPOSITORY_ROOT / path
    if not path.is_file():
        raise ReplayError(f"{label} is absent: {path}")
    actual = _sha256(path)
    if actual != digest.upper():
        raise ReplayError(f"{label} hash differs from its capture record")
    return {"path": str(path.resolve()), "sha256": actual, "bytes": path.stat().st_size}


def _load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReplayError(f"{label} is not valid UTF-8 JSON: {path}") from error


def _normalise_selection(rows: Any, label: str, without_mir: bool) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for index, item in enumerate(_expect_list(rows, label), 1):
        row = _expect_mapping(item, f"{label}[{index}]")
        name = row.get("name")
        version = row.get("version")
        if not isinstance(name, str) or not name or not isinstance(version, str) or not version:
            raise ReplayError(f"{label}[{index}] lacks a mod name/version")
        if without_mir and name == "more-infinite-research":
            continue
        normal = {"name": name, "version": version}
        if "enabled" in row:
            if not isinstance(row["enabled"], bool):
                raise ReplayError(f"{label}[{index}] has a non-boolean enabled field")
            normal["enabled"] = row["enabled"]
        if "builtin" in row:
            if not isinstance(row["builtin"], bool):
                raise ReplayError(f"{label}[{index}] has a non-boolean builtin field")
            normal["builtin"] = row["builtin"]
        if "sha256" in row:
            digest = row["sha256"]
            if not isinstance(digest, str) or len(digest) != 64:
                raise ReplayError(f"{label}[{index}] has an invalid archive SHA-256")
            normal["sha256"] = digest.upper()
        result.append(normal)
    return result


def _read_capture(location: Path, expected_mir: bool) -> dict[str, Any]:
    root = location.resolve()
    if not root.is_dir():
        raise ReplayError(f"capture directory is absent: {root}")
    result_path = root / "result.json"
    if not result_path.is_file():
        raise ReplayError(f"capture result is absent: {result_path}")
    result = _expect_mapping(_load_json(result_path, "capture result"), "capture result")
    process = _expect_mapping(result.get("process"), "capture process")
    if (result.get("status") != "completed-data-stage-observation-only"
            or process.get("passed") is not True
            or process.get("timed_out") is not False
            or process.get("exit_code") != 0):
        raise ReplayError("capture did not complete with a natural zero-exit data-stage observation")

    verified_external: list[dict[str, Any]] = []
    engine_record = _expect_mapping(result.get("engine"), "capture engine")
    verified_external.append(_external_record(engine_record, "capture engine"))
    verified_external.append(_external_record(result.get("profile_input"), "capture profile input"))
    harness = _expect_mapping(result.get("harness"), "capture harness")
    verified_external.append(_external_record(harness, "capture harness"))

    mir = result.get("mir_archive")
    if expected_mir:
        mir = _expect_mapping(mir, "published MIR archive")
        if mir.get("name") != "more-infinite-research" or not isinstance(mir.get("version"), str) or not mir["version"].startswith("4.7."):
            raise ReplayError("published capture must select an exact MIR 4.7 archive")
        verified_external.append(_external_record(mir, "published MIR archive"))
    elif mir is not None:
        raise ReplayError("no-MIR capture unexpectedly selected MIR")

    generated_selection = _expect_mapping(result.get("generated_selection"), "capture generated selection")
    selection_path, selection_file = _recorded_file(root, generated_selection, "generated selection")
    selection = _expect_mapping(_load_json(selection_path, "generated selection"), "generated selection")
    selection_mods = _normalise_selection(selection.get("mods"), "generated selection mods", without_mir=True)
    result_mods = _normalise_selection(generated_selection.get("mods"), "result selection mods", without_mir=True)
    if selection_mods != result_mods:
        raise ReplayError("selection.json differs from the selection recorded by the capture")

    dumps = _expect_mapping(result.get("dumps"), "capture dumps")
    data_path, data_file = _recorded_file(root, dumps.get("data_raw"), "data-raw dump")
    settings_path, settings_file = _recorded_file(root, dumps.get("mod_settings"), "mod-settings dump")
    raw = _expect_mapping(_load_json(data_path, "data-raw dump"), "data-raw dump")
    settings = _expect_mapping(_load_json(settings_path, "mod-settings dump"), "mod-settings dump")

    selected_records = _expect_list(result.get("selected_archives"), "selected archives")
    for index, selected_record in enumerate(selected_records, 1):
        verified_external.append(_external_record(selected_record, f"selected archive {index}"))
    selected = _normalise_selection(selected_records, "selected archives", without_mir=True)
    loaded = result.get("loaded_selection")
    # Early governed one-mod captures recorded the one loaded identity as a
    # scalar.  Preserve that exact receipt input while comparing it as the
    # equivalent one-item selection; newer captures record a list.
    if isinstance(loaded, str):
        loaded = [loaded]
    if not isinstance(loaded, list) or not all(isinstance(value, str) and value for value in loaded):
        raise ReplayError("capture loaded selection is invalid")
    loaded_without_mir = [value for value in loaded if not value.startswith("more-infinite-research@")]
    engine = engine_record
    for field in ("sha256", "base_version", "factorio_version"):
        if not isinstance(engine.get(field), str) or not engine[field]:
            raise ReplayError(f"capture engine lacks {field}")

    return {
        "root": root,
        "result_path": result_path,
        "result": result,
        "raw": raw,
        "settings": settings,
        "engine": {field: engine[field].upper() if field == "sha256" else engine[field]
                   for field in ("sha256", "base_version", "factorio_version")},
        "selection": selection_mods,
        "selected": selected,
        "loaded": loaded_without_mir,
        "files": [
            {"path": "result.json", "sha256": _sha256(result_path), "bytes": result_path.stat().st_size},
            selection_file,
            data_file,
            settings_file,
            *verified_external,
        ],
    }


def _assert_matching_inputs(no_mir: Mapping[str, Any], published: Mapping[str, Any]) -> None:
    if no_mir["engine"] != published["engine"]:
        raise ReplayError("capture engines differ")
    if no_mir["selection"] != published["selection"]:
        raise ReplayError("generated upstream selections differ after removing MIR")
    if no_mir["selected"] != published["selected"]:
        raise ReplayError("selected upstream archive identities differ after removing MIR")
    if no_mir["loaded"] != published["loaded"]:
        raise ReplayError("loaded upstream selections differ after removing MIR")


def _sort_key(value: str) -> bytes:
    return value.encode("utf-8")


def _validate_raw(raw: Mapping[str, Any], label: str) -> None:
    for prototype_type, entries in raw.items():
        if not isinstance(prototype_type, str) or not prototype_type:
            raise ReplayError(f"{label} contains an invalid prototype type")
        prototypes = _expect_mapping(entries, f"{label}.{prototype_type}")
        for name, prototype in prototypes.items():
            if not isinstance(name, str) or not name or not isinstance(prototype, Mapping):
                raise ReplayError(f"{label}.{prototype_type} has an invalid prototype entry")


def _validate_new_prototype(prototype_type: str, name: str, prototype: Mapping[str, Any], label: str) -> None:
    if prototype.get("type") != prototype_type or prototype.get("name") != name:
        raise ReplayError(f"{label} cannot emit {prototype_type}.{name}: captured type/name do not match its data.raw key")


def _changed_fields(before: Any, after: Any, path: tuple[str, ...] = ()) -> list[tuple[tuple[str, ...], Any]]:
    """Return only declared changed fields. Lists are native ordered tuples."""
    if isinstance(before, Mapping) and isinstance(after, Mapping):
        changes: list[tuple[tuple[str, ...], Any]] = []
        for key in sorted(set(before) | set(after), key=_sort_key):
            if key not in after:
                changes.append((path + (key,), None))
            elif key not in before:
                changes.append((path + (key,), after[key]))
            else:
                changes.extend(_changed_fields(before[key], after[key], path + (key,)))
        return changes
    if before == after:
        return []
    return [(path, after)]


def _diff_prototypes(before: Mapping[str, Any], after: Mapping[str, Any], label: str) -> dict[str, Any]:
    _validate_raw(before, f"{label} baseline")
    _validate_raw(after, f"{label} published")
    additions: list[tuple[str, str, Mapping[str, Any]]] = []
    patches: list[tuple[str, str, list[tuple[tuple[str, ...], Any]]]] = []
    deletions: list[tuple[str, str]] = []
    for prototype_type in sorted(set(before) | set(after), key=_sort_key):
        prior = _expect_mapping(before.get(prototype_type, {}), f"{label} baseline.{prototype_type}")
        target = _expect_mapping(after.get(prototype_type, {}), f"{label} published.{prototype_type}")
        for name in sorted(set(prior) | set(target), key=_sort_key):
            if name not in target:
                deletions.append((prototype_type, name))
                continue
            if name not in prior:
                prototype = _expect_mapping(target[name], f"{label} addition {prototype_type}.{name}")
                _validate_new_prototype(prototype_type, name, prototype, label)
                additions.append((prototype_type, name, prototype))
                continue
            old = _expect_mapping(prior[name], f"{label} baseline {prototype_type}.{name}")
            new = _expect_mapping(target[name], f"{label} published {prototype_type}.{name}")
            _validate_new_prototype(prototype_type, name, old, label)
            _validate_new_prototype(prototype_type, name, new, label)
            changes = _changed_fields(old, new)
            if changes:
                if any(path and path[0] in {"type", "name"} for path, _ in changes):
                    raise ReplayError(f"{label} changes immutable identity of {prototype_type}.{name}")
                patches.append((prototype_type, name, changes))
    if deletions:
        listed = ", ".join(f"{prototype_type}.{name}" for prototype_type, name in deletions[:8])
        suffix = "" if len(deletions) <= 8 else f" (+{len(deletions) - 8} more)"
        raise ReplayError(f"{label} contains unsupported whole-prototype deletions: {listed}{suffix}")
    return {"additions": additions, "patches": patches}


def lua_string(value: str) -> str:
    """Quote UTF-8 as Lua 5.2 bytes without JSON's unsupported ``\\u`` escapes."""
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as error:
        raise ReplayError("string contains invalid Unicode") from error
    pieces = ['"']
    for byte in encoded:
        if byte == 34:
            pieces.append('\\"')
        elif byte == 92:
            pieces.append('\\\\')
        elif 32 <= byte <= 126:
            pieces.append(chr(byte))
        else:
            pieces.append(f"\\{byte:03d}")
    pieces.append('"')
    return "".join(pieces)


def lua_value(value: Any, active: set[int] | None = None, in_sequence: bool = False) -> str:
    """Serialize only finite plain JSON/native values into deterministic Lua 5.2."""
    active = set() if active is None else active
    if value is None:
        if in_sequence:
            raise ReplayError("a native tuple/array cannot contain JSON null")
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        if abs(value) > MAX_LUA_NUMBER:
            raise ReplayError("native value contains a nonfinite number")
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ReplayError("native value contains a nonfinite number")
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if not isinstance(value, (Mapping, list, tuple)):
        raise ReplayError(f"unsupported native value type: {type(value).__name__}")
    identity = id(value)
    if identity in active:
        raise ReplayError("native value contains a cycle")
    active.add(identity)
    try:
        lines = ["{"]
        if isinstance(value, Mapping):
            if not all(isinstance(key, str) for key in value):
                raise ReplayError("native map contains a non-string key")
            for key in sorted(value, key=_sort_key):
                lines.append(f"  [{lua_string(key)}] = {lua_value(value[key], active)},")
        else:
            for index, entry in enumerate(value, 1):
                lines.append(f"  [{index}] = {lua_value(entry, active, in_sequence=True)},")
        lines.append("}")
        return "\n".join(lines)
    finally:
        active.remove(identity)


def _lua_path(path: Sequence[str]) -> str:
    return "".join(f"[{lua_string(part)}]" for part in path)


def _render_stage(diff: Mapping[str, Any], stage: str) -> str:
    lines = [
        "-- Generated by tools/mir5/replay.py from exact native captures.",
        "-- Offline diagnostic reference only; this does not qualify player behavior.",
    ]
    additions = diff["additions"]
    if additions:
        lines.append("data:extend({")
        for _, _, prototype in additions:
            lines.extend(f"  {line}" for line in lua_value(prototype).splitlines())
            lines[-1] += ","
        lines.append("})")
    for prototype_type, name, changes in diff["patches"]:
        base = f"data.raw[{lua_string(prototype_type)}][{lua_string(name)}]"
        # A Lua chunk may contain no more than 200 locals.  Keep each target's
        # temporary binding in its own block so a large diagnostic diff stays
        # executable under the pinned Lua 5.2 host.
        lines.append("do")
        lines.append(f"  local prototype = {base}")
        lines.append(f"  if prototype == nil then error({lua_string('replay missing existing prototype ' + prototype_type + '.' + name)}) end")
        for path, value in changes:
            if not path:
                raise ReplayError(f"{stage} patch unexpectedly replaces an entire prototype")
            lines.append(f"  prototype{_lua_path(path)} = {lua_value(value)}")
        lines.append("end")
    if not additions and not diff["patches"]:
        lines.append("-- Captures had no differences for this stage.")
    return "\n".join(lines) + "\n"


def _render_empty_entrypoint(name: str) -> str:
    return ("-- Deliberately empty offline replay entrypoint.\n"
            f"-- {name} must not start the retired MIR compiler.\n")


def _input_inventory(capture: Mapping[str, Any], role: str) -> list[dict[str, Any]]:
    return [
        {"role": role, "path": str(capture["root"] / row["path"]), "sha256": row["sha256"], "bytes": row["bytes"]}
        for row in capture["files"]
    ]


def build_replay(no_mir_capture: Path, published_capture: Path, output_root: Path) -> dict[str, Any]:
    """Validate captures, render an offline diagnostic replay, and return its receipt."""
    no_mir = _read_capture(no_mir_capture, expected_mir=False)
    published = _read_capture(published_capture, expected_mir=True)
    _assert_matching_inputs(no_mir, published)

    data_before = {kind: entries for kind, entries in no_mir["raw"].items() if not kind.endswith(SETTING_SUFFIX)}
    data_after = {kind: entries for kind, entries in published["raw"].items() if not kind.endswith(SETTING_SUFFIX)}
    data_diff = _diff_prototypes(data_before, data_after, "data stage")
    settings_diff = _diff_prototypes(no_mir["settings"], published["settings"], "settings stage")

    rendered: dict[str, bytes] = {
        DATA_OUTPUT: _render_stage(data_diff, "data stage").encode("utf-8"),
        SETTINGS_OUTPUT: _render_stage(settings_diff, "settings stage").encode("utf-8"),
    }
    rendered.update({name: _render_empty_entrypoint(name).encode("utf-8") for name in EMPTY_ENTRYPOINTS})

    output = output_root.resolve()
    if output.exists():
        raise ReplayError(f"output root must be fresh: {output}")
    if not output.parent.is_dir():
        raise ReplayError(f"output parent is absent: {output.parent}")
    output.mkdir()
    try:
        for name, content in rendered.items():
            (output / name).write_bytes(content)
        outputs = [
            {"path": name, "sha256": _sha256(output / name), "bytes": (output / name).stat().st_size}
            for name in sorted(rendered, key=_sort_key)
        ]
        receipt = {
            "schema": 1,
            "kind": "MIR5OfflineDiagnosticReplayV1",
            "status": "generated-offline-diagnostic-not-native-evidence",
            "claims": {"native_qualification": False, "player_package": False, "replay_execution": False},
            "profile_specific": True,
            "engine": no_mir["engine"],
            "published_mir": {
                "name": published["result"]["mir_archive"]["name"],
                "version": published["result"]["mir_archive"]["version"],
            },
            "comparison": {
                "data_additions": len(data_diff["additions"]),
                "data_patches": len(data_diff["patches"]),
                "settings_additions": len(settings_diff["additions"]),
                "settings_patches": len(settings_diff["patches"]),
                "whole_prototype_deletions": 0,
                "unfiltered_prototype_types": True,
            },
            "inputs": _input_inventory(no_mir, "no-mir-native-capture")
                      + _input_inventory(published, "published-mir-4.7-native-capture"),
            "outputs": outputs,
        }
        receipt_bytes = _json_bytes(receipt)
        (output / RECEIPT_OUTPUT).write_bytes(receipt_bytes)
        inventory = {
            "schema": 1,
            "kind": "MIR5OfflineDiagnosticReplayHashInventoryV1",
            "inputs": receipt["inputs"],
            "outputs": outputs + [{"path": RECEIPT_OUTPUT, "sha256": hashlib.sha256(receipt_bytes).hexdigest().upper(), "bytes": len(receipt_bytes)}],
        }
        inventory_bytes = _json_bytes(inventory)
        (output / INVENTORY_OUTPUT).write_bytes(inventory_bytes)
        return receipt
    except Exception:
        shutil.rmtree(output)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-mir-capture", type=Path, required=True)
    parser.add_argument("--published-capture", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        receipt = build_replay(args.no_mir_capture, args.published_capture, args.output_root)
    except ReplayError as error:
        print(f"[mir5-replay] {error}", file=sys.stderr)
        return 2
    print(json.dumps({"status": receipt["status"], "output_root": str(args.output_root.resolve())}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
