"""Execute bounded lab-reference binding controls; never starts Factorio."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo_root).resolve()
    sys.path.insert(0, str(Path(args.lua_runtime_dir).resolve()))
    from lupa import lua52

    lua = lua52.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().repo_source = (repo / "source").as_posix()
    lua.execute(
        """
        package.path = repo_source .. '/?.lua;' .. package.path
        data = {raw = {}, extend = function() error('No test mutation admission') end}
        mods = {base = '2.0.77'}
        log = function() end
        package.loaded['prototypes.mir.platform.factorio.target_profiles'] = {
          current = function() return {prototype_shapes = {}} end
        }
        for _, name in ipairs({'pack_production_reachability', 'recipe_route_feasibility',
                              'production_route_policy', 'technology_researchability'}) do
          package.preload['prototypes.mir.capabilities.science_integration.' .. name] = function()
            error('Prohibited former discovery module: ' .. name)
          end
        end
        """
    )
    fixture = repo / "tests/compiler/lab_bindings.lua"
    assertions = lua.execute(fixture.read_text(encoding="utf-8"))
    inputs = [
        Path("source/prototypes/mir/capabilities/science_integration/lab_bindings.lua"),
        Path("tests/compiler/lab_bindings.lua"),
        Path("tests/compiler/run_lab_bindings_controls.py"),
    ]
    print(json.dumps({
        "status": "MIR-APPROVED-LAB-BINDINGS-PASSED",
        "assertions": assertions,
        "factorio_processes": 0,
        "runtime": "Lua 5.2",
        "scope": "controlled-approved-lab-references-not-factory-acquisition-or-native-qualification",
        "sources": {path.as_posix(): digest(repo / path) for path in inputs},
    }, sort_keys=True))


if __name__ == "__main__":
    main()
