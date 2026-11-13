#!/usr/bin/env python3
"""Bounded Linux resource observations for the MIR native-process governor.

This helper deliberately reads only procfs accounting and cgroup-v2 control
files.  It never reads process command lines, environments, open-file tables,
or Factorio data.  JSON on stdout is the sole interface; callers treat every
malformed or unavailable required observation as a refusal.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import posixpath
import re
import sys
from pathlib import Path
from typing import Any


class ObservationFailure(Exception):
    """A stable, non-diagnostic failure code for the PowerShell boundary."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def fail(code: str) -> None:
    raise ObservationFailure(code)


def read_text(path: Path, code: str) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        fail(code)
    raise AssertionError("unreachable")


def parse_uint(value: str, code: str) -> int:
    if not re.fullmatch(r"[0-9]+", value):
        fail(code)
    try:
        return int(value)
    except ValueError:
        fail(code)
    raise AssertionError("unreachable")


def read_meminfo(proc_root: Path) -> dict[str, int]:
    found: dict[str, int] = {}
    for line in read_text(proc_root / "meminfo", "mir441-linux-proc-meminfo").splitlines():
        match = re.fullmatch(r"(MemTotal|MemAvailable):\s*([0-9]+)\s+kB\s*", line)
        if match is None:
            continue
        key = match.group(1)
        if key in found:
            fail("mir441-linux-proc-meminfo")
        found[key] = parse_uint(match.group(2), "mir441-linux-proc-meminfo") * 1024
    if set(found) != {"MemTotal", "MemAvailable"} or found["MemAvailable"] > found["MemTotal"]:
        fail("mir441-linux-proc-meminfo")
    return {"total_bytes": found["MemTotal"], "available_bytes": found["MemAvailable"]}


def unescape_mount(value: str, code: str) -> str:
    def replacement(match: re.Match[str]) -> str:
        return chr(int(match.group(1), 8))

    try:
        return re.sub(r"\\([0-7]{3})", replacement, value)
    except ValueError:
        fail(code)
    raise AssertionError("unreachable")


def cgroup_self_path(proc_root: Path) -> str:
    selected: list[str] = []
    for line in read_text(proc_root / "self" / "cgroup", "mir441-linux-cgroup-v2").splitlines():
        fields = line.split(":", 2)
        if len(fields) == 3 and fields[0] == "0" and fields[1] == "":
            selected.append(fields[2])
    if len(selected) != 1 or not selected[0].startswith("/") or "\x00" in selected[0]:
        fail("mir441-linux-cgroup-v2")
    return selected[0]


def cgroup_mount(proc_root: Path) -> tuple[str, Path]:
    selected: list[tuple[str, Path]] = []
    for line in read_text(proc_root / "self" / "mountinfo", "mir441-linux-cgroup-v2").splitlines():
        pieces = line.split(" - ", 1)
        if len(pieces) != 2:
            fail("mir441-linux-cgroup-v2")
        before, after = pieces
        fields = before.split()
        trailer = after.split()
        if len(fields) < 5 or not trailer:
            fail("mir441-linux-cgroup-v2")
        if trailer[0] != "cgroup2":
            continue
        selected.append((unescape_mount(fields[3], "mir441-linux-cgroup-v2"), Path(unescape_mount(fields[4], "mir441-linux-cgroup-v2"))))
    if len(selected) != 1:
        fail("mir441-linux-cgroup-v2")
    return selected[0]


def mount_identity(proc_root: Path, path: str) -> dict[str, int | str]:
    if "\x00" in path or not path.startswith("/"):
        fail("mir441-linux-mount-identity")
    candidate = posixpath.normpath(path)
    matches: list[tuple[int, int, int, str, str]] = []
    for index, line in enumerate(read_text(proc_root / "self" / "mountinfo", "mir441-linux-mount-identity").splitlines()):
        pieces = line.split(" - ", 1)
        if len(pieces) != 2:
            fail("mir441-linux-mount-identity")
        before, after = pieces
        fields = before.split()
        trailer = after.split()
        if len(fields) < 5 or len(trailer) < 3:
            fail("mir441-linux-mount-identity")
        mount_id = parse_uint(fields[0], "mir441-linux-mount-identity")
        mount_point = unescape_mount(fields[4], "mir441-linux-mount-identity")
        if not mount_point.startswith("/") or "\x00" in mount_point:
            fail("mir441-linux-mount-identity")
        prefix = mount_point.rstrip("/") or "/"
        contained = candidate == prefix or (prefix != "/" and candidate.startswith(prefix + "/")) or prefix == "/"
        if contained:
            matches.append((len(prefix), index, mount_id, mount_point, trailer[0]))
    if not matches:
        fail("mir441-linux-mount-identity")
    _, _, mount_id, mount_point, filesystem_type = max(matches, key=lambda row: (row[0], row[1]))
    return {"mount_id": mount_id, "mount_point": mount_point, "filesystem_type": filesystem_type}


def cgroup_leaf(mount_root: str, mount_point: Path, cgroup_path: str) -> Path:
    root = mount_root.rstrip("/") or "/"
    if root == "/":
        relative = cgroup_path.lstrip("/")
    elif cgroup_path == root:
        relative = ""
    elif cgroup_path.startswith(root + "/"):
        relative = cgroup_path[len(root) + 1 :]
    else:
        fail("mir441-linux-cgroup-v2")
    if any(part in {"", ".", ".."} for part in relative.split("/") if relative):
        fail("mir441-linux-cgroup-v2")
    try:
        base = mount_point.resolve(strict=True)
        leaf = (base / relative).resolve(strict=True)
        if os.path.commonpath((str(base), str(leaf))) != str(base):
            fail("mir441-linux-cgroup-v2")
    except OSError:
        fail("mir441-linux-cgroup-v2")
    return leaf


def read_cgroup_limit(path: Path, code: str) -> int | None:
    value = read_text(path, code).strip()
    if value == "max":
        return None
    return parse_uint(value, code)


def read_cgroup_current(path: Path, code: str) -> int:
    return parse_uint(read_text(path, code).strip(), code)


def read_counter_map(path: Path, code: str) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in read_text(path, code).splitlines():
        fields = line.split()
        if len(fields) != 2 or not re.fullmatch(r"[a-z_]+", fields[0]) or fields[0] in values:
            fail(code)
        values[fields[0]] = parse_uint(fields[1], code)
    required = {"low", "high", "max", "oom", "oom_kill"}
    if not required.issubset(values):
        fail(code)
    return values


def read_pressure(path: Path, code: str) -> dict[str, dict[str, int | float]]:
    output: dict[str, dict[str, int | float]] = {}
    for line in read_text(path, code).splitlines():
        fields = line.split()
        if len(fields) != 5 or fields[0] not in {"some", "full"} or fields[0] in output:
            fail(code)
        row: dict[str, int | float] = {}
        for field in fields[1:]:
            key, separator, value = field.partition("=")
            if separator != "=" or key in row or key not in {"avg10", "avg60", "avg300", "total"}:
                fail(code)
            if key == "total":
                row[key] = parse_uint(value, code)
            else:
                try:
                    parsed = float(value)
                except ValueError:
                    fail(code)
                if not math.isfinite(parsed) or parsed < 0:
                    fail(code)
                row[key] = parsed
        if set(row) != {"avg10", "avg60", "avg300", "total"}:
            fail(code)
        output[fields[0]] = row
    if set(output) != {"some", "full"}:
        fail(code)
    return output


def cgroup_snapshot(proc_root: Path) -> dict[str, Any]:
    group_path = cgroup_self_path(proc_root)
    mount_root, mount_point = cgroup_mount(proc_root)
    leaf = cgroup_leaf(mount_root, mount_point, group_path)
    try:
        mount_resolved = mount_point.resolve(strict=True)
    except OSError:
        fail("mir441-linux-cgroup-v2")

    ancestors: list[dict[str, Any]] = []
    current = leaf
    while True:
        controls = (
            current / "memory.current",
            current / "memory.max",
            current / "memory.high",
            current / "memory.events",
            current / "memory.events.local",
        )
        present = [path.exists() for path in controls]
        is_actual_hierarchy_root = current == mount_resolved and mount_root == "/"
        if is_actual_hierarchy_root and not any(present):
            relative = current.relative_to(mount_resolved).as_posix()
            ancestors.append(
                {
                    "relative_path": "/" if relative == "." else "/" + relative,
                    "control_applicability": "root-control-not-applicable",
                    "current_bytes": None,
                    "max_bytes": None,
                    "high_bytes": None,
                    "max_headroom_bytes": None,
                    "high_headroom_bytes": None,
                    "effective_headroom_bytes": None,
                    "events": None,
                    "events_local": None,
                    "pressure": read_pressure(current / "memory.pressure", "mir441-linux-cgroup-pressure"),
                }
            )
            break
        maximum = read_cgroup_limit(current / "memory.max", "mir441-linux-cgroup-memory")
        high = read_cgroup_limit(current / "memory.high", "mir441-linux-cgroup-memory")
        used = read_cgroup_current(current / "memory.current", "mir441-linux-cgroup-memory")
        if (maximum is not None and used > maximum) or (high is not None and used > high):
            fail("mir441-linux-cgroup-memory")
        max_headroom = None if maximum is None else maximum - used
        high_headroom = None if high is None else high - used
        finite = [value for value in (max_headroom, high_headroom) if value is not None]
        relative = current.relative_to(mount_resolved).as_posix()
        ancestors.append(
            {
                "relative_path": "/" if relative == "." else "/" + relative,
                "control_applicability": "applicable",
                "current_bytes": used,
                "max_bytes": maximum,
                "high_bytes": high,
                "max_headroom_bytes": max_headroom,
                "high_headroom_bytes": high_headroom,
                "effective_headroom_bytes": min(finite) if finite else None,
                "events": read_counter_map(current / "memory.events", "mir441-linux-cgroup-events"),
                "events_local": read_counter_map(current / "memory.events.local", "mir441-linux-cgroup-events"),
                "pressure": read_pressure(current / "memory.pressure", "mir441-linux-cgroup-pressure"),
            }
        )
        if current == mount_resolved:
            break
        parent = current.parent
        if parent == current:
            fail("mir441-linux-cgroup-v2")
        current = parent
    finite_headrooms = [row["effective_headroom_bytes"] for row in ancestors if row["effective_headroom_bytes"] is not None]
    return {
        "version": "v2",
        "self_path": group_path,
        "leaf_relative_path": ancestors[0]["relative_path"],
        "effective_headroom_bytes": min(finite_headrooms) if finite_headrooms else None,
        "ancestors": ancestors,
    }


def read_proc_stat(proc_root: Path, pid: int, *, missing_is_exit: bool) -> dict[str, int] | None:
    path = proc_root / str(pid) / "stat"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        if missing_is_exit:
            return None
        fail("mir441-linux-process-stat")
    except (OSError, UnicodeError):
        fail("mir441-linux-process-stat")
    close = text.rfind(")")
    if close < 3 or not text.startswith(str(pid) + " ("):
        fail("mir441-linux-process-stat")
    fields = text[close + 1 :].split()
    if len(fields) <= 19:
        fail("mir441-linux-process-stat")
    return {
        "pid": pid,
        "ppid": parse_uint(fields[1], "mir441-linux-process-stat"),
        "session_id": parse_uint(fields[3], "mir441-linux-process-stat"),
        "start_ticks": parse_uint(fields[19], "mir441-linux-process-stat"),
    }


def iter_proc_stats(proc_root: Path) -> list[dict[str, int]]:
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        fail("mir441-linux-process-stat")
    rows: list[dict[str, int]] = []
    for entry in entries:
        if not entry.name.isascii() or not entry.name.isdecimal():
            continue
        pid = parse_uint(entry.name, "mir441-linux-process-stat")
        if pid <= 0:
            fail("mir441-linux-process-stat")
        row = read_proc_stat(proc_root, pid, missing_is_exit=True)
        if row is not None:
            rows.append(row)
    return rows


def read_status_rss(proc_root: Path, pid: int) -> int:
    value: int | None = None
    for line in read_text(proc_root / str(pid) / "status", "mir441-linux-process-status").splitlines():
        match = re.fullmatch(r"VmRSS:\s*([0-9]+)\s+kB\s*", line)
        if match is not None:
            if value is not None:
                fail("mir441-linux-process-status")
            value = parse_uint(match.group(1), "mir441-linux-process-status") * 1024
    if value is None:
        fail("mir441-linux-process-status")
    return value


def read_private_memory(proc_root: Path, pid: int) -> tuple[int, int]:
    wanted = {"Private_Clean", "Private_Dirty", "Private_Hugetlb", "Swap"}
    values: dict[str, int] = {}
    for line in read_text(proc_root / str(pid) / "smaps_rollup", "mir441-linux-process-smaps").splitlines():
        match = re.fullmatch(r"([A-Za-z_]+):\s*([0-9]+)\s+kB\s*", line)
        if match is None or match.group(1) not in wanted:
            continue
        name = match.group(1)
        if name in values:
            fail("mir441-linux-process-smaps")
        values[name] = parse_uint(match.group(2), "mir441-linux-process-smaps") * 1024
    if not {"Private_Clean", "Private_Dirty", "Swap"}.issubset(values):
        fail("mir441-linux-process-smaps")
    resident = values["Private_Clean"] + values["Private_Dirty"] + values.get("Private_Hugetlb", 0)
    return resident, values["Swap"]


def task_children(proc_root: Path, pid: int) -> set[int]:
    task_root = proc_root / str(pid) / "task"
    try:
        tasks = list(task_root.iterdir())
    except FileNotFoundError:
        return set()
    except OSError:
        fail("mir441-linux-process-children")
    output: set[int] = set()
    for task in tasks:
        if not task.name.isascii() or not task.name.isdecimal():
            fail("mir441-linux-process-children")
        children_path = task / "children"
        try:
            text = children_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            continue
        except (OSError, UnicodeError):
            fail("mir441-linux-process-children")
        for value in text.split():
            child = parse_uint(value, "mir441-linux-process-children")
            if child <= 0:
                fail("mir441-linux-process-children")
            output.add(child)
    return output


def process_identity(proc_root: Path, pid: int) -> dict[str, int | bool]:
    if pid <= 0:
        fail("mir441-linux-process-stat")
    row = read_proc_stat(proc_root, pid, missing_is_exit=True)
    if row is None:
        return {"pid": pid, "exited": True}
    return {"pid": row["pid"], "start_ticks": row["start_ticks"], "session_id": row["session_id"]}


def process_tree(proc_root: Path, root_pid: int, root_start_ticks: int, session_id: int | None) -> dict[str, Any]:
    root = read_proc_stat(proc_root, root_pid, missing_is_exit=True)
    if root is not None and root["start_ticks"] != root_start_ticks:
        fail("mir441-owned-root-identity")
    if session_id is not None:
        if session_id <= 0 or session_id != root_pid:
            fail("mir441-owned-session-identity")
        if root is not None and root["session_id"] != session_id:
            fail("mir441-owned-session-identity")
        owned = {row["pid"]: row for row in iter_proc_stats(proc_root) if row["session_id"] == session_id}
        if root is not None and root_pid not in owned:
            fail("mir441-owned-session-identity")
    elif root is None:
        return {
            "root_exited": True,
            "root_identity": {"pid": root_pid, "start_ticks": root_start_ticks},
            "working_set_bytes": 0,
            "private_resident_bytes": 0,
            "private_swap_bytes": 0,
            "private_bytes": 0,
            "private_measure": "smaps_rollup_private_resident_plus_swap",
            "children": [],
        }
    else:
        queue = [root]
        owned = {root_pid: root}
        while queue:
            parent = queue.pop(0)
            for child_pid in task_children(proc_root, parent["pid"]):
                child = read_proc_stat(proc_root, child_pid, missing_is_exit=True)
                if child is None:
                    continue
                if child["ppid"] != parent["pid"] or child["start_ticks"] < root_start_ticks:
                    fail("mir441-owned-child-identity")
                prior = owned.get(child_pid)
                if prior is not None:
                    if prior["start_ticks"] != child["start_ticks"]:
                        fail("mir441-owned-child-identity")
                    continue
                owned[child_pid] = child
                queue.append(child)

    working = 0
    private_resident = 0
    private_swap = 0
    children: list[dict[str, int]] = []
    for pid in sorted(owned):
        row = owned[pid]
        current = read_proc_stat(proc_root, pid, missing_is_exit=True)
        if current is None:
            continue
        if current["start_ticks"] != row["start_ticks"] or (session_id is not None and current["session_id"] != session_id):
            fail("mir441-owned-child-identity")
        working += read_status_rss(proc_root, pid)
        resident, swap = read_private_memory(proc_root, pid)
        private_resident += resident
        private_swap += swap
        if pid != root_pid:
            children.append({"id": pid, "start_ticks": row["start_ticks"], "session_id": row["session_id"]})
    return {
        "root_exited": root is None,
        "root_identity": {"pid": root_pid, "start_ticks": root_start_ticks, "session_id": session_id},
        "working_set_bytes": working,
        "private_resident_bytes": private_resident,
        "private_swap_bytes": private_swap,
        "private_bytes": private_resident + private_swap,
        "private_measure": "smaps_rollup_private_resident_plus_swap",
        "children": children,
    }


def result(value: dict[str, Any]) -> int:
    print(json.dumps({"ok": True, "value": value}, separators=(",", ":"), sort_keys=True))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "mount-identity", "process-identity", "process-tree"))
    parser.add_argument("--proc-root", default="/proc")
    parser.add_argument("--path")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--root-start-ticks", type=int)
    parser.add_argument("--session-id", type=int)
    args = parser.parse_args(argv)
    proc_root = Path(args.proc_root)
    try:
        if args.command == "snapshot":
            return result({"memory": read_meminfo(proc_root), "cgroup_v2": cgroup_snapshot(proc_root)})
        if args.command == "mount-identity":
            if args.path is None:
                fail("mir441-linux-mount-identity")
            return result(mount_identity(proc_root, args.path))
        if args.pid is None:
            fail("mir441-linux-process-stat")
        if args.command == "process-identity":
            return result(process_identity(proc_root, args.pid))
        if args.root_start_ticks is None or args.root_start_ticks < 0:
            fail("mir441-linux-process-stat")
        return result(process_tree(proc_root, args.pid, args.root_start_ticks, args.session_id))
    except ObservationFailure as error:
        print(json.dumps({"ok": False, "code": error.code}, separators=(",", ":"), sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
