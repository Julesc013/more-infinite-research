#!/usr/bin/env python3
"""Create one owned POSIX session, receipt it, then exec an exact target.

This is intentionally a tiny Linux-only launch boundary, not a scheduler. The
governor supplies an already-admitted receipt path and exact executable/argv.
The launcher never searches PATH or invokes a shell.
"""

from __future__ import annotations

import json
import os
import stat
import sys
from pathlib import Path


def start_ticks(pid: int) -> int:
    text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    close = text.rfind(")")
    if close < 3 or not text.startswith(f"{pid} ("):
        raise ValueError("stat")
    fields = text[close + 1 :].split()
    if len(fields) <= 19 or not fields[19].isdigit():
        raise ValueError("stat")
    return int(fields[19])


def write_receipt(path: Path, value: dict[str, int | str]) -> None:
    if not path.is_absolute() or "\x00" in str(path):
        raise ValueError("receipt")
    parent = path.parent
    parent_stat = os.lstat(parent)
    if not stat.S_ISDIR(parent_stat.st_mode) or stat.S_ISLNK(parent_stat.st_mode):
        raise ValueError("receipt-parent")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if not hasattr(os, "O_NOFOLLOW"):
        raise ValueError("no-follow")
    descriptor = os.open(path, flags | os.O_NOFOLLOW, 0o600)
    try:
        payload = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        written = 0
        while written < len(payload):
            count = os.write(descriptor, payload[written:])
            if count <= 0:
                raise OSError("receipt-write")
            written += count
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[0] != "--receipt" or argv[2] != "--":
        return 125
    receipt = Path(argv[1])
    target = argv[3]
    target_argv = argv[3:]
    if not os.path.isabs(target) or "\x00" in target:
        return 125
    try:
        os.setsid()
        pid = os.getpid()
        session_id = os.getsid(0)
        if session_id != pid:
            return 125
        write_receipt(
            receipt,
            {
                "kind": "MIR441LinuxNativeLaunchV1",
                "pid": pid,
                "session_id": session_id,
                "start_ticks": start_ticks(pid),
            },
        )
        os.execv(target, target_argv)
    except (OSError, UnicodeError, ValueError):
        return 125
    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
