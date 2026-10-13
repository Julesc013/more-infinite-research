#!/usr/bin/env python3
"""Run source-bound Classic compatibility-cycle controls through Lua 5.2."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    fixture_path = repo / "tests/compiler/classic_compatibility_cycle_bounds.lua"
    source_paths = [
        repo / "source/prototypes/mir/compatibility/repairs/registry.lua",
        repo / "source/prototypes/mir/compatibility/repairs/technology_prerequisite_cycles.lua",
    ]
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    quoted_root = str(repo / "source").replace("\\", "/").replace("'", "\\'")
    runtime.execute("package.path = '" + quoted_root + "/?.lua;" + quoted_root + "/?/init.lua;' .. package.path")
    result = runtime.execute(fixture_path.read_text(encoding="utf-8"))
    material = b"".join(path.read_bytes() for path in source_paths)
    record = {
        "status": "MIR-CLASSIC-COMPATIBILITY-CYCLE-BOUNDS-PASSED",
        "assertions": int(result["assertions"]),
        "source_sha256": hashlib.sha256(material).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture_path.read_bytes()).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
