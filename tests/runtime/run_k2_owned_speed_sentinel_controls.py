from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    runtime = args.lua_runtime_dir.resolve()
    if not runtime.is_dir():
        raise ValueError(f"--lua-runtime-dir is not a directory: {runtime}")
    if str(runtime) not in sys.path:
        sys.path.insert(0, str(runtime))
    from lupa import lua52

    sentinel = repo / "fixtures/aaa-mir47-owned-speed-sentinel/control.lua"
    fixture = repo / "fixtures/assert-upgrade-k2-imersite-4-6-21000-to-4-7-21000/control.lua"
    lifecycle_controls = repo / "tests/runtime/k2_owned_speed_sentinel_controls.lua"
    fixture_controls = repo / "tests/runtime/k2_owned_speed_sentinel_fixture_controls.lua"
    source = sentinel.read_text(encoding="utf-8")
    full_fixture_source = fixture.read_text(encoding="utf-8")
    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().MIR47_OWNED_SPEED_SENTINEL_SOURCE = source
    lua.globals().MIR47_K2_FULL_FIXTURE_SOURCE = full_fixture_source
    lifecycle_assertions = int(lua.execute(lifecycle_controls.read_text(encoding="utf-8")))
    fixture_assertions = int(lua.execute(fixture_controls.read_text(encoding="utf-8")))
    receipt = {
        "schema": 2,
        "kind": "MIR47OwnedSpeedSentinelHostControlsV2",
        "status": "passed",
        "scope": (
            "host-only owned-sentinel lifecycle plus full source-fixture lexical and "
            "LuaRemote-interface-shape controls; not native Factorio callback-order, "
            "prototype-migration, or opaque-third-party-effect preservation evidence"
        ),
        "assertions": lifecycle_assertions + fixture_assertions,
        "assertion_groups": {
            "companion_lifecycle": lifecycle_assertions,
            "complete_fixture_source_phase": fixture_assertions,
        },
        "factorio_invoked": False,
        "inputs": {
            "sentinel_control_sha256": digest(sentinel),
            "k2_fixture_control_sha256": digest(fixture),
            "lifecycle_controls_sha256": digest(lifecycle_controls),
            "fixture_controls_sha256": digest(fixture_controls),
            "runner_sha256": digest(Path(__file__)),
            "lua_runtime_dir": str(runtime),
            "runtime": "lupa.lua52",
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())