#!/usr/bin/env python3
"""Run source-bound private witness-memo controls under the local Lua 5.2 runtime.

The controls create no Factorio fixture, package, engine process, or archive.
They establish only the guarded private-DAG and public-isolation semantics.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua")
FIXTURE_PATH = Path("tests/compiler/witness_memo_isolation.lua")
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
M.__mir_witness_memo_test_hooks = {
  copy_options = copy_options,
  clone_witness_graph = clone_witness_graph,
  retain_witness_memo = retain_witness_memo,
  memo_witness_for_caller = memo_witness_for_caller,
  private_witness_memo_allowed = private_witness_memo_allowed,
  initial_failure_probe = initial_failure_probe,
  retire_private_probe_witness_memos = retire_private_probe_witness_memos,
  acquisition_witness_impl = acquisition_witness_impl
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
_G.TEST_TELEMETRY = {}
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {
    source_epoch = function() return "memo-epoch" end,
    index_view = function() return _G.TEST_RECIPE_INDEX end
  }
end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return _G.TEST_COMPILER_CONTEXT end}
end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {count = function(name, amount)
    _G.TEST_TELEMETRY[name] = (_G.TEST_TELEMETRY[name] or 0) + (amount or 1)
  end}
end
"""
    )
    module = runtime.execute(instrument_source(source))
    runtime.globals().WITNESS_MEMO_MODULE = module
    runtime.globals().WITNESS_MEMO_HOOKS = module["__mir_witness_memo_test_hooks"]
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-WITNESS-MEMO-ISOLATION-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "private_hits": int(result["private_hits"]),
        "isolated_hits": int(result["isolated_hits"]),
        "graph_clone_calls": int(result["graph_clone_calls"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
