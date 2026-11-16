#!/usr/bin/env python3
"""Create one owned POSIX session, receipt it, then exec an exact target.

This is intentionally a tiny Linux-only launch boundary, not a scheduler. The
governor supplies an already-admitted receipt path and exact executable/argv.
The launcher never searches PATH or invokes a shell.
"""

from __future__ import annotations

import json
import os
import secrets
import select
import stat
import sys
import time
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


def write_exclusive_json(path: Path, value: dict[str, int | str]) -> None:
    if not path.is_absolute() or "\x00" in str(path):
        raise ValueError("path")
    parent = path.parent
    parent_stat = os.lstat(parent)
    if not stat.S_ISDIR(parent_stat.st_mode) or stat.S_ISLNK(parent_stat.st_mode):
        raise ValueError("parent")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if not hasattr(os, "O_NOFOLLOW"):
        raise ValueError("no-follow")
    # Publishing the final pathname with O_EXCL would expose an incomplete
    # receipt to the governor between open() and fsync().  Write a private
    # same-directory file, then link it into place atomically.  link() is both
    # no-replace and no-follow at the destination, while the temporary file
    # retains the exact exclusive/no-follow creation boundary.
    temporary = parent / f".{path.name}.{os.getpid()}.{secrets.token_hex(16)}.tmp"
    descriptor = os.open(temporary, flags | os.O_NOFOLLOW, 0o600)
    try:
        payload = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
        written = 0
        while written < len(payload):
            count = os.write(descriptor, payload[written:])
            if count <= 0:
                raise OSError("write")
            written += count
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.link(temporary, path, follow_symlinks=False)
        directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
        directory_descriptor = os.open(parent, directory_flags)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def valid_bound_value(value: object, kind: str) -> bool:
    if not isinstance(value, dict) or set(value) != {"kind", "pid", "session_id", "start_ticks"}:
        return False
    if value["kind"] != kind:
        return False
    return all(type(value[name]) is int and value[name] > 0 for name in ("pid", "session_id", "start_ticks")) and value["pid"] == value["session_id"]


def wait_for_ack(expected: dict[str, int | str], timeout_seconds: float = 2.0) -> bool:
    # Only the inherited parent pipe authorizes execution. Receipt-derived
    # values in a filesystem ACK cannot establish that the parent adopted us.
    deadline = time.monotonic() + timeout_seconds
    payload = bytearray()
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([0], [], [], remaining)[0]:
            return False
        byte = os.read(0, 1)
        if not byte or len(payload) >= 1024:
            return False
        if byte == b"\n":
            try:
                value = json.loads(payload.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                return False
            return valid_bound_value(value, "MIR441LinuxNativeAckV1") and value == expected
        payload.extend(byte)
    return False


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
        receipt_value: dict[str, int | str] = {
            "kind": "MIR441LinuxNativeLaunchV1",
            "pid": pid,
            "session_id": session_id,
            "start_ticks": start_ticks(pid),
        }
        write_exclusive_json(
            receipt,
            receipt_value,
        )
        ack_value = dict(receipt_value)
        ack_value["kind"] = "MIR441LinuxNativeAckV1"
        if not wait_for_ack(ack_value):
            return 125
        os.execv(target, target_argv)
    except (OSError, UnicodeError, ValueError):
        return 125
    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
