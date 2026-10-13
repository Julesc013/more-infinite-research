#!/usr/bin/env python3
"""Run private witness-traversal controls against the exact Lua source.

This is a source-bound Lua 5.2/Lupa control.  It writes no Factorio fixture,
package, archive, or engine output and cannot establish native behavior.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
FIXTURE_PATH = Path("tests/compiler/witness_graph_traversal.lua")
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
M.__mir_witness_graph_test_hooks = {
  acquisition_children = acquisition_children,
  witness_avoids_active_identities = witness_avoids_active_identities,
  memo_witness_identity_summary = memo_witness_identity_summary,
  positive_witness_reusable = positive_witness_reusable,
  witness_unlock_dependencies = witness_unlock_dependencies,
  selected_research_unlock_pairs = selected_research_unlock_pairs
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
    from lupa import lua52  # Imported only from the already-provided local runtime.

    source_path = repo / SOURCE_PATH
    fixture_path = repo / FIXTURE_PATH
    source = source_path.read_text(encoding="utf-8")
    fixture = fixture_path.read_text(encoding="utf-8")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
local function empty_module() return {} end
for _, name in ipairs({
  "prototypes.mir.capabilities.science_integration.pack_registry",
  "prototypes.mir.capabilities.science_integration.recipe_unlock_facts",
  "prototypes.mir.index.recipe_facts",
  "prototypes.mir.platform.factorio.data_raw",
  "prototypes.mir.core.deepcopy",
  "prototypes.mir.pipeline.compiler_context",
  "prototypes.mir.graph.researchability_index",
  "prototypes.mir.capabilities.science_integration.technology_researchability",
  "prototypes.mir.capabilities.science_integration.production_route_policy",
  "prototypes.mir.report.compiler_telemetry"
}) do
  package.preload[name] = empty_module
end
package.preload["prototypes.mir.capabilities.science_integration.recipe_route_feasibility"] = function()
  return {
    acquisition_key = function(identity)
      _G.__witness_identity_calls = (_G.__witness_identity_calls or 0) + 1
      return identity.type .. "\\0" .. identity.name
    end
  }
end
"""
    )
    module = runtime.execute(instrument_source(source))
    runtime.globals().WITNESS_GRAPH_HOOKS = module["__mir_witness_graph_test_hooks"]
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-WITNESS-GRAPH-TRAVERSAL-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "alias_identity_calls": int(result["alias_identity_calls"]),
        "naive_alias_identity_calls": int(result["naive_alias_identity_calls"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
