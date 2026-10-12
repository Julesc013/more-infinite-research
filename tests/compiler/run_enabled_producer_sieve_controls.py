#!/usr/bin/env python3
"""Exercise the canonical enabled-producer sieve without starting Factorio.

The fixture loads the real route-feasibility module with a minimal immutable
recipe-index Context.  It verifies only selection scheduling and diagnostic
boundaries; it makes no native-performance claim.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/recipe_route_feasibility.lua")
FIXTURE_PATH = Path("tests/compiler/enabled_producer_sieve.lua")
RETURN_MARKER = "\nreturn M"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


def instrument(source: str) -> str:
    position = source.rfind(RETURN_MARKER)
    if position < 0 or source[position + len(RETURN_MARKER) :].strip():
        raise RuntimeError("Expected the canonical feasibility module to end with exactly return M")
    hooks = """
M.__mir_enabled_producer_sieve_test_hooks = {
  sorted_producers = sorted_producers,
  has_enabled_visible_variant = has_enabled_visible_variant,
  may_sieve_enabled_producers = may_sieve_enabled_producers
}
return M
"""
    return source[:position] + "\n" + hooks


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    source = (repo / SOURCE_PATH).read_text(encoding="utf-8")
    fixture = (repo / FIXTURE_PATH).read_text(encoding="utf-8")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
local function graph_copy(value, copied)
  if type(value) ~= "table" then return value end
  copied = copied or {}
  if copied[value] then return copied[value] end
  local result = {}
  copied[value] = result
  for key, member in pairs(value) do
    result[graph_copy(key, copied)] = graph_copy(member, copied)
  end
  return result
end

local empty = {}
_G.TEST_SIEVE_CONTEXT = {states = {}}
function _G.TEST_SIEVE_CONTEXT:state_view(name, factory)
  if self.states[name] == nil and factory then self.states[name] = factory() end
  return self.states[name]
end
function _G.TEST_SIEVE_CONTEXT:set_state(name, value) self.states[name] = value; return value end
function _G.TEST_SIEVE_CONTEXT:replace_epoch(name, value) self.states[name] = value; return value end
function _G.TEST_SIEVE_CONTEXT:state_epoch(_) return 1 end
function _G.TEST_SIEVE_CONTEXT:service(_) return nil end

package.preload["prototypes.mir.core.deepcopy"] = function() return graph_copy end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function()
  return {
    prototypes = function(_) return empty end,
    prototype = function(_, _) return nil end,
    technology = function(_) return nil end,
    feature_enabled = function(_) return false end
  }
end
package.preload["prototypes.mir.platform.factorio.target_profiles"] = function()
  return {
    current = function() return {prototype_shapes = {product_probability_fields = {}}} end,
    current_factorio_version = "2.1"
  }
end
package.preload["prototypes.mir.platform.factorio.prototype_lookup"] = function()
  return {item_prototype = function(_) return nil end, item_types = function() return {} end}
end
package.preload["prototypes.mir.index.item_prototype_facts"] = function()
  return {placeable_items_for_entity = function(_) return {} end}
end
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {
    source_epoch = function() return "enabled-producer-sieve-epoch" end,
    index_view = function() return _G.TEST_SIEVE_CONTEXT.states.recipe_index end
  }
end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return _G.TEST_SIEVE_CONTEXT end}
end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {count = function(name, amount)
    _G.TEST_SIEVE_TELEMETRY = _G.TEST_SIEVE_TELEMETRY or {}
    _G.TEST_SIEVE_TELEMETRY[name] = (_G.TEST_SIEVE_TELEMETRY[name] or 0) + (amount or 1)
  end}
end
"""
    )
    module = runtime.execute(instrument(source))
    runtime.globals().ENABLED_PRODUCER_SIEVE_MODULE = module
    runtime.globals().ENABLED_PRODUCER_SIEVE_HOOKS = module[
        "__mir_enabled_producer_sieve_test_hooks"
    ]
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-ENABLED-PRODUCER-SIEVE-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "cold_sieved": int(result["cold_sieved"]),
        "filtered": int(result["filtered"]),
        "complete": int(result["complete"]),
        "research_calls": int(result["research_calls"]),
        "warm_bucket_reads": int(result["warm_bucket_reads"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
