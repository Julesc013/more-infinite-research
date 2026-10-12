#!/usr/bin/env python3
"""Run the source-bound classic/full routing control under Lua 5.2.

No Factorio process or package is created.  The test exercises the actual
profile reader and stage modules, substituting only branch sentinels so it can
prove that selecting classic never loads the full compiler path.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


FIXTURE = Path("tests/compiler/classic_profile_routing.lua")
SOURCES = (
    Path("source/prototypes/mir/settings/compiler_profile.lua"),
    Path("source/prototypes/mir/stage/data.lua"),
    Path("source/prototypes/mir/stage/data_final_fixes.lua"),
    Path("source/prototypes/mir/pipeline/classic_compiler.lua"),
    Path("source/prototypes/mir/planner/classic/plan.lua"),
    Path("source/prototypes/mir/planner/classic/declarations.lua"),
    Path("source/prototypes/mir/planner/compiler.lua"),
)


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
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    fixture = repo / FIXTURE
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    adapter = repo / "source" / "adapters" / args.target
    runtime.execute(
        'package.path = "' + lua_path(repo / "source" / "?.lua") + ";"
        + lua_path(adapter / "?.lua") + ';" .. package.path'
    )
    runtime.globals().MIR_CLASSIC_ROUTING_TARGET = args.target
    result = runtime.execute(fixture.read_text(encoding="utf-8"))
    record = {
        "status": "MIR-CLASSIC-PROFILE-ROUTING-CONTROLS-PASSED",
        "target": args.target,
        "assertions": int(result["assertions"]),
        "classic_calls": int(result["classic_calls"]),
        "full_calls": int(result["full_calls"]),
        "historic_full_calls": int(result["historic_full_calls"]),
        "source_sha256": source_digest(repo),
        "fixture_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    if (record["assertions"] < 16 or record["classic_calls"] != 1
            or record["full_calls"] != 1 or record["historic_full_calls"] != 1):
        raise RuntimeError(f"Unexpected classic profile routing result: {record}")
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
