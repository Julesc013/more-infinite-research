#!/usr/bin/env python3
"""Run private stable-witness DAG controls against the exact Lua source.

This source-bound Lua 5.2/Lupa check creates no Factorio fixture, package,
archive or engine process. It establishes only classifier equivalence and
private-query boundaries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua")
FIXTURE_PATH = Path("tests/compiler/stable_witness_dag.lua")
RETURN_MARKER = "\nreturn M"


def read_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


def instrument_source(source: str) -> str:
    marker_at = source.rfind(RETURN_MARKER)
    if marker_at < 0 or source[marker_at + len(RETURN_MARKER):].strip():
        raise RuntimeError("Expected the canonical module to end with one return M")
    hooks = """
M.__mir_private_stable_witness_dag_test_hooks = {
  stable_acquisition_witness = stable_acquisition_witness,
  stable_acquisition_witness_for_query = stable_acquisition_witness_for_query,
  private_witness_memo_allowed = private_witness_memo_allowed
}
return M
"""
    return source[:marker_at] + "\n" + hooks


def main() -> int:
    args = read_args()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    source_path = repo / SOURCE_PATH
    fixture_path = repo / FIXTURE_PATH
    source = source_path.read_text(encoding="utf-8")
    fixture = fixture_path.read_text(encoding="utf-8")
    private_call = "stable_acquisition_witness_for_query(witness, share_private_memo)"
    if source.count(private_call) != 2 or source.count(
        "stable_acquisition_witness_for_query(direct, share_private_memo)"
    ) != 1:
        raise RuntimeError("All three stable-memo admission sites must use the existing private-query guard")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
local empty = function() return {} end
for _, name in ipairs({
  "prototypes.mir.platform.factorio.data_raw",
  "prototypes.mir.platform.factorio.target_profiles",
  "prototypes.mir.core.deepcopy",
  "prototypes.mir.platform.factorio.prototype_lookup",
  "prototypes.mir.index.item_prototype_facts"
}) do package.preload[name] = empty end

_G.TEST_RECIPE_INDEX = {facts = {}}
_G.TEST_PRODUCTION_STATE = {}
_G.TEST_COMPILER_CONTEXT = {
  state_view = function(_, name)
    if name == "recipe_index" then return _G.TEST_RECIPE_INDEX end
    if name == "science_pack_production" then return _G.TEST_PRODUCTION_STATE end
    return nil
  end
}
_G.TEST_OTHER_CONTEXT = {
  state_view = _G.TEST_COMPILER_CONTEXT.state_view
}
_G.TEST_CURRENT_CONTEXT = _G.TEST_COMPILER_CONTEXT
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {
    source_epoch = function() return "stable-witness-epoch" end,
    index_view = function() return _G.TEST_RECIPE_INDEX end
  }
end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return _G.TEST_CURRENT_CONTEXT end}
end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {count = function() end}
end
"""
    )
    module = runtime.execute(instrument_source(source))
    runtime.globals().STABLE_WITNESS_DAG_MODULE = module
    runtime.globals().STABLE_WITNESS_DAG_HOOKS = module[
        "__mir_private_stable_witness_dag_test_hooks"
    ]
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-PRIVATE-STABLE-WITNESS-DAG-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "alias_nodes": int(result["alias_nodes"]),
        "alias_hits": int(result["alias_hits"]),
        "unshared_nodes": int(result["unshared_nodes"]),
        "wide_nodes": int(result["wide_nodes"]),
        "small_old_seconds": float(result["small_old_seconds"]),
        "small_private_seconds": float(result["small_private_seconds"]),
        "alias_old_seconds": float(result["alias_old_seconds"]),
        "alias_private_seconds": float(result["alias_private_seconds"]),
        "unshared_old_seconds": float(result["unshared_old_seconds"]),
        "unshared_private_seconds": float(result["unshared_private_seconds"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
