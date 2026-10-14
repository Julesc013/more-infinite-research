#!/usr/bin/env python3
"""Run single-compiler Research Library controls under Lua 5.2."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

FIXTURE = Path("tests/runtime/classic_profile_browser_status.lua")
SOURCES = (
    Path("source/prototypes/mir/runtime/research_browser_mir_provider.lua"),
    Path("source/prototypes/mir/runtime/research_browser_core.lua"),
    Path("source/prototypes/mir/runtime/research_browser.lua"),
)
RETIRED = Path("source/prototypes/mir/domain/compiler/classic_declarations.lua")

def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    parser.add_argument("--target", required=True, choices=("f200", "f210"))
    return parser.parse_args()

def lua_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/").replace('"', '\\"')

def source_digest(repo: Path) -> str:
    digest = hashlib.sha256()
    for source in SOURCES:
        digest.update(source.as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update((repo / source).read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()

def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    if (repo / RETIRED).exists():
        raise RuntimeError(f"Retired Classic declaration remains installed: {RETIRED.as_posix()}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    adapter = repo / "source" / "adapters" / args.target
    runtime.execute('package.path = "' + lua_path(repo / "source" / "?.lua") + ";"
                    + lua_path(adapter / "?.lua") + ';" .. package.path')
    result = runtime.execute((repo / FIXTURE).read_text(encoding="utf-8"))
    record = {
        "status": "MIR-SINGLE-COMPILER-BROWSER-CONTROLS-PASSED",
        "target": args.target,
        "assertions": int(result["assertions"]),
        "source_sha256": source_digest(repo),
        "fixture_sha256": hashlib.sha256((repo / FIXTURE).read_bytes()).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    if record["assertions"] < 5:
        raise RuntimeError(f"Incomplete single compiler browser result: {record}")
    print(json.dumps(record, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
