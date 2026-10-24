#!/usr/bin/env python3
"""Read bounded native MIR Library profiler markers without scoring them.

The reader accepts exactly one explicit server, English-client, and
German-client log.  It retains the complete marker-bearing line and the
identity of each input log, but never copies unrelated log output.  It does
not compute an aggregate, a threshold, or a performance verdict.
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


KIND = "MIR5LibraryProfilerObservationV1"
ROLES = ("server", "en", "de")
ACTIONS = ("first_open", "search", "refresh", "reopen")
MARKER_TOKEN = "[MIR5_LIBRARY_PROFILE]"
MARKER = MARKER_TOKEN + " "
MAX_LOG_BYTES = 8 * 1024 * 1024
MAX_LINE_CHARACTERS = 16 * 1024

# Factorio renders a LuaProfiler through a LocalisedString.  These are the
# observed English and German renderings; accepting another unit or caption
# would conceal a parser/engine format drift as a timing observation.
ENGLISH = re.compile(r"^(?P<action>first_open|search|refresh|reopen) Duration: "
                    r"(?P<value>(?:0|[1-9][0-9]*)(?:\.[0-9]+)?)ms$")
GERMAN = re.compile(r"^(?P<action>first_open|search|refresh|reopen) Dauer: "
                   r"(?P<value>(?:0|[1-9][0-9]*)(?:\.[0-9]+)?)\u202fms$")


class LibraryProfileError(ValueError):
    """A profiler input is absent, malformed, or outside this narrow contract."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def _parse_log_argument(value: str) -> tuple[str, Path]:
    role, separator, raw_path = value.partition("=")
    if separator != "=" or role not in ROLES or not raw_path:
        raise LibraryProfileError("--log must be one of server=PATH, en=PATH, or de=PATH")
    return role, Path(raw_path)


def _read_log(path: Path) -> tuple[bytes, list[str]]:
    try:
        # Do not use Path.read_bytes(): this reader must reject an oversized
        # native log before allocating an unbounded input in the host process.
        # A bounded read also handles a log which grows after any metadata
        # observation.
        with path.open("rb") as stream:
            data = stream.read(MAX_LOG_BYTES + 1)
    except OSError as error:
        raise LibraryProfileError(f"log is unreadable: {path}") from error
    if len(data) > MAX_LOG_BYTES:
        raise LibraryProfileError(f"log exceeds {MAX_LOG_BYTES} byte input limit: {path}")
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


def read_profiles(logs: Iterable[tuple[str, Path]]) -> dict[str, Any]:
    """Return raw marker observations or an explicit incomplete observation.

    Inputs are intentionally fixed to the native session's three roles.  A
    prior failed session can retain the observed first three actions, which is
    useful diagnostic evidence but never a complete performance sample.
    """
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

    role_rows: list[dict[str, Any]] = []
    complete = True
    for role in ROLES:
        path = selected[role]
        data, lines = _read_log(path)
        observations: dict[str, dict[str, Any]] = {}
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
            }
        missing_actions = [action for action in ACTIONS if action not in observations]
        if missing_actions:
            complete = False
        role_rows.append({
            "role": role,
            "log_path": str(path),
            "log_sha256": _sha256(data),
            "log_bytes": len(data),
            "observations": [observations[action] for action in ACTIONS if action in observations],
            "missing_actions": missing_actions,
        })

    return {
        "schema": 1,
        "kind": KIND,
        "status": "complete-observation" if complete else "incomplete-observation",
        "complete": complete,
        "timing_verdict": "none",
        "performance_acceptance": False,
        "roles": role_rows,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", action="append", required=True, metavar="ROLE=PATH",
                        help="exactly one server, en, and de native log")
    args = parser.parse_args(argv)
    try:
        result = read_profiles(_parse_log_argument(value) for value in args.log)
    except LibraryProfileError as error:
        print(f"[mir5-library-profile-reader] {error}", file=sys.stderr)
        return 2
    # Native German profiler text contains U+202F.  Emit UTF-8 directly so a
    # Windows console code page cannot turn a valid observation into a crash.
    sys.stdout.buffer.write((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
