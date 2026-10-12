#!/usr/bin/env python3
"""Exercise the public item-acquisition service against an internal DAG witness.

This is a source-bound Lua 5.2 control only. It starts no Factorio process and
does not create a package, archive, or fixture directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
FIXTURE_PATH = Path("tests/compiler/item_acquisition_service_isolation.lua")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


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
  local out = {}
  copied[value] = out
  for key, member in pairs(value) do out[graph_copy(key, copied)] = graph_copy(member, copied) end
  return out
end

local context = {states = {}, epochs = {}}
function context:state_view(name, factory)
  if self.states[name] == nil and factory then self.states[name] = factory() end
  return self.states[name]
end
function context:set_state(name, value) self.states[name] = value; return value end
function context:replace_epoch(name, value) self.states[name] = value; return value end
function context:state_epoch(name) return self.epochs[name] or 0 end
function context:service() return nil end

_G.TEST_PRIVATE_WITNESS = {
  kind = "private-root",
  output = {type = "item", name = "public-item"},
  ingredients = {{kind = "private-child"}},
  machine = {launcher = {kind = "private-launcher"}}
}
_G.TEST_ACQUISITION_CALLS = {}

package.preload["prototypes.mir.core.deepcopy"] = function() return graph_copy end
package.preload["prototypes.mir.capabilities.science_integration.pack_registry"] = function() return {} end
package.preload["prototypes.mir.capabilities.science_integration.recipe_unlock_facts"] = function() return {} end
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {source_epoch = function() return "service-epoch" end}
end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function() return {} end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return context end}
end
package.preload["prototypes.mir.graph.researchability_index"] = function() return {} end
package.preload["prototypes.mir.capabilities.science_integration.production_route_policy"] = function() return {} end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {count = function() end, observe_max = function() end}
end
package.preload["prototypes.mir.capabilities.science_integration.recipe_route_feasibility"] = function()
  return {
    enable_compiler_owned_witness_sharing = function(options)
      options.private_marker = true
      return options
    end,
    acquisition_witness = function(identity, options, state)
      table.insert(_G.TEST_ACQUISITION_CALLS, {identity = identity, options = options, state = state})
      return _G.TEST_PRIVATE_WITNESS
    end
  }
end
"""
    )
    module = runtime.execute(source)
    runtime.globals().ITEM_ACQUISITION_SERVICE_MODULE = module
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-ITEM-ACQUISITION-SERVICE-ISOLATION-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "calls": int(result["calls"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
