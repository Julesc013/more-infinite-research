#!/usr/bin/env python3
"""Read bounded native MIR Library profiler markers without scoring them.

The direct command line accepts exactly one explicit server, English-client,
and German-client log. An optional small manifest retains the native process
phase for up to three selected logs per role. Neither input form computes a
threshold, aggregate, or performance verdict.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import re
import sys
from typing import Any, Iterable


KIND = "MIR5LibraryProfilerObservationV1"
MANIFEST_KIND = "MIR5LibraryProfilerLogManifestV1"
ROLES = ("server", "en", "de")
ACTIONS = ("first_open", "search", "refresh", "reopen")
PROCESS_LABELS = ("initial", "rejoin", "restart")
DIRECT_PROCESS_LABEL = "direct"
MARKER_TOKEN = "[MIR5_LIBRARY_PROFILE]"
MARKER = MARKER_TOKEN + " "
MAX_LOG_BYTES = 8 * 1024 * 1024
MAX_MANIFEST_BYTES = 64 * 1024
MAX_LOGS_PER_ROLE = 3
MAX_TOTAL_LOG_BYTES = 24 * 1024 * 1024
MAX_LINE_CHARACTERS = 16 * 1024

# Factorio renders a LuaProfiler through a LocalisedString. These are the
# observed English and German renderings; accepting another unit or caption
# would conceal a parser/engine format drift as a timing observation.
ENGLISH = re.compile(r"^(?P<action>first_open|search|refresh|reopen) Duration: "
                    r"(?P<value>(?:0|[1-9][0-9]*)(?:\.[0-9]+)?)ms$")
GERMAN = re.compile(r"^(?P<action>first_open|search|refresh|reopen) Dauer: "
                   r"(?P<value>(?:0|[1-9][0-9]*)(?:\.[0-9]+)?)\u202fms$")


class LibraryProfileError(ValueError):
    """A profiler input is absent, malformed, or outside this narrow contract."""


@dataclass(frozen=True)
class LogInput:
    role: str
    process: str
    path: Path
    original_path: str


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def _parse_log_argument(value: str) -> tuple[str, Path]:
    role, separator, raw_path = value.partition("=")
    if separator != "=" or role not in ROLES or not raw_path:
        raise LibraryProfileError("--log must be one of server=PATH, en=PATH, or de=PATH")
    return role, Path(raw_path)


def _read_bounded(path: Path, maximum_bytes: int, description: str) -> bytes:
    try:
        # Do not use Path.read_bytes(): inputs can grow after metadata was
        # observed, so the host must request no more than its declared bound.
        with path.open("rb") as stream:
            data = stream.read(maximum_bytes + 1)
    except OSError as error:
        raise LibraryProfileError(f"{description} is unreadable: {path}") from error
    if len(data) > maximum_bytes:
        raise LibraryProfileError(f"{description} exceeds {maximum_bytes} byte input limit: {path}")
    return data


def _read_log(path: Path) -> tuple[bytes, list[str]]:
    data = _read_bounded(path, MAX_LOG_BYTES, "log")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise LibraryProfileError(f"log is not UTF-8: {path}") from error
    lines = text.splitlines()
    if any(len(line) > MAX_LINE_CHARACTERS for line in lines):
        raise LibraryProfileError(f"log line exceeds {MAX_LINE_CHARACTERS} character limit: {path}")
    return data, lines


def _parse_marker(role: str, raw_line: str) -> tuple[str, float]:
    suffix = raw_line[raw_line.index(MARKER) + len(MARKER):]
    grammar = ENGLISH if role in {"server", "en"} else GERMAN
    match = grammar.fullmatch(suffix)
    if match is None:
        raise LibraryProfileError(f"{role} profiler marker has an unknown format or unit: {raw_line!r}")
    value = float(match.group("value"))
    if not math.isfinite(value) or value < 0:
        raise LibraryProfileError(f"{role} profiler duration is not finite and nonnegative: {raw_line!r}")
    return match.group("action"), value


def _read_profiles(inputs: Iterable[LogInput], *, manifest: dict[str, Any] | None = None) -> dict[str, Any]:
    grouped: dict[str, list[LogInput]] = {role: [] for role in ROLES}
    for entry in inputs:
        if entry.role not in grouped:
            raise LibraryProfileError(f"unexpected input role: {entry.role}")
        grouped[entry.role].append(entry)
    if any(not grouped[role] for role in ROLES):
        missing = ", ".join(role for role in ROLES if not grouped[role])
        raise LibraryProfileError(f"exactly server, en, and de inputs are required (missing roles: {missing})")
    if any(len(grouped[role]) > MAX_LOGS_PER_ROLE for role in ROLES):
        raise LibraryProfileError(f"each role permits at most {MAX_LOGS_PER_ROLE} selected logs")

    role_rows: list[dict[str, Any]] = []
    total_bytes = 0
    for role in ROLES:
        observations: dict[str, dict[str, Any]] = {}
        log_rows: list[dict[str, Any]] = []
        for entry in grouped[role]:
            data, lines = _read_log(entry.path)
            total_bytes += len(data)
            if total_bytes > MAX_TOTAL_LOG_BYTES:
                raise LibraryProfileError(f"selected logs exceed {MAX_TOTAL_LOG_BYTES} byte total input limit")
            log_hash = _sha256(data)
            log_row = {
                "process": entry.process,
                "original_path": entry.original_path,
                "log_path": str(entry.path),
                "log_sha256": log_hash,
                "log_bytes": len(data),
            }
            log_rows.append(log_row)
            for raw_line in lines:
                if MARKER_TOKEN not in raw_line:
                    continue
                if raw_line.count(MARKER_TOKEN) != 1:
                    raise LibraryProfileError(f"{role} profiler marker is duplicated: {raw_line!r}")
                if MARKER not in raw_line:
                    raise LibraryProfileError(f"{role} profiler marker lacks its required separator: {raw_line!r}")
                action, duration = _parse_marker(role, raw_line)
                if action in observations:
                    raise LibraryProfileError(f"{role} profiler action is duplicated: {action}")
                observations[action] = {
                    "action": action,
                    "duration_ms": duration,
                    "raw_line": raw_line,
                    "process": entry.process,
                    "original_path": entry.original_path,
                    "log_path": str(entry.path),
                    "log_sha256": log_hash,
                }
        missing_actions = [action for action in ACTIONS if action not in observations]
        row: dict[str, Any] = {
            "role": role,
            "logs": log_rows,
            "observations": [observations[action] for action in ACTIONS if action in observations],
            "missing_actions": missing_actions,
        }
        # Preserve the original direct three-log result shape for callers that
        # only need one log locator and identity per role.
        if len(log_rows) == 1:
            row.update({key: log_rows[0][key] for key in ("log_path", "log_sha256", "log_bytes")})
        role_rows.append(row)

    complete = all(not row["missing_actions"] for row in role_rows)
    result: dict[str, Any] = {
        "schema": 1,
        "kind": KIND,
        "status": "complete-observation" if complete else "incomplete-observation",
        "complete": complete,
        "timing_verdict": "none",
        "performance_acceptance": False,
        "roles": role_rows,
    }
    if manifest is not None:
        result["manifest"] = manifest
    return result


def read_profiles(logs: Iterable[tuple[str, Path]]) -> dict[str, Any]:
    """Read the original exact-three-log command-line input form."""
    selected: dict[str, Path] = {}
    for role, path in logs:
        if role in selected:
            raise LibraryProfileError(f"duplicate input role: {role}")
        selected[role] = path
    if set(selected) != set(ROLES):
        missing = ", ".join(role for role in ROLES if role not in selected)
        unexpected = ", ".join(sorted(set(selected) - set(ROLES)))
        detail = "; ".join(value for value in (
            f"missing roles: {missing}" if missing else "",
            f"unexpected roles: {unexpected}" if unexpected else "",
        ) if value)
        raise LibraryProfileError(f"exactly server, en, and de inputs are required ({detail})")
    return _read_profiles(
        (LogInput(role, DIRECT_PROCESS_LABEL, path, str(path)) for role, path in selected.items())
    )


def _manifest_path(manifest_path: Path, original_path: str) -> Path:
    candidate = Path(original_path)
    if not original_path or candidate.is_absolute() or "\x00" in original_path:
        raise LibraryProfileError("manifest log path must be a nonempty relative path")
    root = manifest_path.parent.resolve()
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise LibraryProfileError("manifest log path escapes the manifest directory") from error
    return resolved


def _strict_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, member in pairs:
        if key in value:
            raise LibraryProfileError(f"manifest contains duplicate JSON key: {key}")
        value[key] = member
    return value


def _reject_json_constant(value: str) -> None:
    raise LibraryProfileError(f"manifest contains nonfinite JSON constant: {value}")


def read_manifest(manifest_path: Path) -> dict[str, Any]:
    """Read the fixed three-role phase manifest without selecting a latest log."""
    data = _read_bounded(manifest_path, MAX_MANIFEST_BYTES, "manifest")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_strict_json_object,
            parse_constant=_reject_json_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LibraryProfileError(f"manifest is not strict UTF-8 JSON: {manifest_path}") from error
    if not isinstance(value, dict) or set(value) != {"schema", "kind", "roles"}:
        raise LibraryProfileError("manifest keys differ")
    if type(value["schema"]) is not int or value["schema"] != 1 or value["kind"] != MANIFEST_KIND or not isinstance(value["roles"], dict):
        raise LibraryProfileError("manifest schema differs")
    if set(value["roles"]) != set(ROLES):
        raise LibraryProfileError("manifest roles must be exactly server, en, and de")

    entries: list[LogInput] = []
    seen_locators: set[str] = set()
    for role in ROLES:
        records = value["roles"][role]
        if not isinstance(records, list) or not records or len(records) > MAX_LOGS_PER_ROLE:
            raise LibraryProfileError(f"{role} manifest logs must contain one to {MAX_LOGS_PER_ROLE} entries")
        seen_processes: set[str] = set()
        by_process: dict[str, dict[str, Any]] = {}
        for record in records:
            if not isinstance(record, dict) or set(record) != {"process", "path"}:
                raise LibraryProfileError(f"{role} manifest entry keys differ")
            process, original_path = record["process"], record["path"]
            if not isinstance(process, str) or process not in PROCESS_LABELS or process in seen_processes:
                raise LibraryProfileError(f"{role} manifest process must be a unique initial, rejoin, or restart label")
            if not isinstance(original_path, str):
                raise LibraryProfileError(f"{role} manifest path is not a string")
            seen_processes.add(process)
            by_process[process] = record
        for process in PROCESS_LABELS:
            if process in by_process:
                record = by_process[process]
                original_path = record["path"]
                path = _manifest_path(manifest_path, original_path)
                locator = str(path).casefold()
                if locator in seen_locators:
                    raise LibraryProfileError("manifest log locator is duplicated")
                seen_locators.add(locator)
                entries.append(LogInput(role, process, path, original_path))

    return _read_profiles(
        entries,
        manifest={
            "path": str(manifest_path),
            "sha256": _sha256(data),
            "bytes": len(data),
        },
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", action="append", metavar="ROLE=PATH",
                        help="one direct server, en, or de native log")
    parser.add_argument("--manifest", metavar="PATH",
                        help="small JSON manifest for named initial/rejoin/restart logs")
    args = parser.parse_args(argv)
    if bool(args.log) == bool(args.manifest):
        parser.error("provide either exact --log inputs or one --manifest, not both")
    try:
        result = read_manifest(Path(args.manifest)) if args.manifest else read_profiles(
            _parse_log_argument(value) for value in args.log
        )
    except LibraryProfileError as error:
        print(f"[mir5-library-profile-reader] {error}", file=sys.stderr)
        return 2
    # Native German profiler text contains U+202F. Emit UTF-8 directly so a
    # Windows console code page cannot turn a valid observation into a crash.
    sys.stdout.buffer.write((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
