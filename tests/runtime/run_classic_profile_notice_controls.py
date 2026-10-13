#!/usr/bin/env python3
"""Run source-bound Classic saved-investment notice controls under Lua 5.2."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

FIXTURE = Path("tests/runtime/classic_profile_notice.lua")
SOURCES = (
    Path("source/prototypes/mir/runtime/compiler_profile_notice.lua"),
    Path("source/prototypes/mir/settings/compiler_profile.lua"),
    Path("source/adapters/f200/prototypes/mir/runtime/scripted_techs.lua"),
    Path("source/adapters/f210/prototypes/mir/runtime/scripted_techs.lua"),
    Path("source/locale/en/more-infinite-research.cfg"),
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


def digest(repo: Path) -> str:
    result = hashlib.sha256()
    for source in SOURCES:
        result.update(source.as_posix().encode("utf-8"))
        result.update(b"\0")
        result.update((repo / source).read_bytes())
        result.update(b"\0")
    return result.hexdigest()


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    notice_source = (repo / SOURCES[0]).read_text(encoding="utf-8")
    locale_source = (repo / SOURCES[-1]).read_text(encoding="utf-8")
    required_locale = (
        "[mir-message]",
        "classic-profile-initial-scope=",
        "classic-profile-existing-save-scope=",
        "classic-profile-upgrade-warning=",
        "MIR 4.2 generated research, levels, effects, and current research progress",
        "untouched backup",
        "Full before loading",
    )
    if not all(value in locale_source for value in required_locale):
        raise RuntimeError("Classic saved-investment warning localisation is incomplete")
    if "function M.on_load()" not in notice_source or "script.on_event(defines.events.on_tick" not in notice_source:
        raise RuntimeError("Classic notice lacks the reviewed conditional one-shot load path")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    fixture = runtime.execute((repo / FIXTURE).read_text(encoding="utf-8"))
    adapters = runtime.table_from({
        "f200": (repo / SOURCES[2]).read_text(encoding="utf-8"),
        "f210": (repo / SOURCES[3]).read_text(encoding="utf-8"),
    })
    result = fixture(notice_source, adapters)
    record = {
        "status": "MIR-CLASSIC-PROFILE-NOTICE-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "source_sha256": digest(repo),
        "fixture_sha256": hashlib.sha256((repo / FIXTURE).read_bytes()).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    if record["assertions"] < 13:
        raise RuntimeError(f"Incomplete Classic notice controls: {record}")
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())