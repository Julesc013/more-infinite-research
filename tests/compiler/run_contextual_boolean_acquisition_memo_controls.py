#!/usr/bin/env python3
"""Exercise the bounded Boolean acquisition memo without starting Factorio.

The production reachability module is loaded from source.  The compact Lua
world controls only Context epochs, canonical services, and acquisition-result
timing so each refusal path has an opposing cold fallback assertion.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("source/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
FIXTURE_PATH = Path("tests/compiler/contextual_boolean_acquisition_memo.lua")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


BOOTSTRAP = r'''
local function graph_copy(value, copied)
  if type(value) ~= "table" then return value end
  copied = copied or {}
  if copied[value] then return copied[value] end
  local out = {}
  copied[value] = out
  for key, member in pairs(value) do out[graph_copy(key, copied)] = graph_copy(member, copied) end
  return out
end

_G.TEST_BOOLEAN_SOURCE_EPOCH = "boolean-epoch-a"
_G.TEST_BOOLEAN_ACQUISITION_CALLS = 0
_G.TEST_BOOLEAN_RETURN_FALSE = false
_G.TEST_BOOLEAN_MUTATE_ROOT = false
_G.TEST_BOOLEAN_MUTATE_STABLE = false
_G.TEST_BOOLEAN_MUTATE_PACK_GUARDS = nil
_G.TEST_BOOLEAN_MUTATE_RECIPE_EPOCH = false
_G.TEST_BOOLEAN_MUTATE_SOURCE = false
_G.TEST_BOOLEAN_WITNESS = {
  kind = "boolean-private-root",
  output = {type = "item", name = "lab-kit"},
  child = {kind = "private-child"}
}

local context = {states = {}, epochs = {}, services = {}}
function context:state_view(name, factory)
  if self.states[name] == nil and factory then
    self.states[name] = factory()
    self.epochs[name] = self.epochs[name] or 1
  end
  return self.states[name]
end
function context:set_state(name, value)
  self.states[name] = value
  self.epochs[name] = self.epochs[name] or 1
  return value
end
function context:replace_epoch(name, value)
  self.states[name] = value
  self.epochs[name] = (self.epochs[name] or 0) + 1
  return value
end
function context:state_epoch(name) return self.epochs[name] end
function context:service(name) return self.services[name] end
_G.TEST_BOOLEAN_CONTEXT = context

local recipe_index = {kind = "recipe-index"}
local research_index = {index_fingerprint = "research-index-a"}
local state = {
  recipe_source_epoch = _G.TEST_BOOLEAN_SOURCE_EPOCH,
  recipe_index = recipe_index,
  stable_acquisition_generation = 1,
  visiting = {}
}
local owner = {
  recipe_source_epoch = _G.TEST_BOOLEAN_SOURCE_EPOCH,
  route_witness_state = state,
  root_entry_generation = 0,
  entries = {},
  contextual_pack_status_memo = {},
  contextual_pack_status_count = 0,
  technology_mechanism_memo = {}
}
context.states.recipe_index = recipe_index
context.epochs.recipe_index = 7
context.states.technology_researchability_index = research_index
context.epochs.technology_researchability_index = 11
context.states.science_pack_production = owner
context.epochs.science_pack_production = 1
context.states.compiler_telemetry = {counters = {}, phases = {}, witnesses = {}}
context.epochs.compiler_telemetry = 1
_G.TEST_BOOLEAN_STATE = state
_G.TEST_BOOLEAN_REPLACE_ROUTE_STATE = function()
  local replacement = {
    recipe_source_epoch = _G.TEST_BOOLEAN_SOURCE_EPOCH,
    recipe_index = recipe_index,
    stable_acquisition_generation = state.stable_acquisition_generation,
    visiting = {}
  }
  owner.route_witness_state = replacement
  _G.TEST_BOOLEAN_STATE = replacement
  return replacement
end
_G.TEST_BOOLEAN_OWNER = owner

package.preload["prototypes.mir.core.deepcopy"] = function() return graph_copy end
package.preload["prototypes.mir.capabilities.science_integration.pack_registry"] = function() return {} end
package.preload["prototypes.mir.capabilities.science_integration.recipe_unlock_facts"] = function() return {} end
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {source_epoch = function() return _G.TEST_BOOLEAN_SOURCE_EPOCH end}
end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function() return {} end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return context end}
end
package.preload["prototypes.mir.graph.researchability_index"] = function() return {} end
local tech_reason = function() return nil end
_G.TEST_BOOLEAN_TECH_REASON = tech_reason
package.preload["prototypes.mir.capabilities.science_integration.technology_researchability"] = function()
  return {reason_with_context = tech_reason}
end
package.preload["prototypes.mir.capabilities.science_integration.production_route_policy"] = function() return {} end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  local function counters()
    return context:state_view("compiler_telemetry").counters
  end
  return {
    count = function(name, amount)
      local values = counters()
      values[name] = (values[name] or 0) + (amount or 1)
    end,
    observe_max = function(name, value)
      local values = counters()
      values[name] = math.max(values[name] or 0, value or 0)
    end
  }
end
package.preload["prototypes.mir.capabilities.science_integration.recipe_route_feasibility"] = function()
  return {
    enable_compiler_owned_witness_sharing = function(options)
      options.private_marker = true
      return options
    end,
    state_context_matches = function(candidate, expected)
      return candidate == _G.TEST_BOOLEAN_STATE and expected == context
    end,
    acquisition_witness = function(identity, options, candidate_state)
      _G.TEST_BOOLEAN_ACQUISITION_CALLS = _G.TEST_BOOLEAN_ACQUISITION_CALLS + 1
      assert(identity.type == "item" and type(identity.name) == "string", "expected typed item identity")
      if options.diagnostic_observer ~= nil then
        return _G.TEST_BOOLEAN_RETURN_FALSE and nil or _G.TEST_BOOLEAN_WITNESS
      end
      assert(candidate_state == _G.TEST_BOOLEAN_STATE and options.private_marker, "expected canonical private acquisition path")
      if _G.TEST_BOOLEAN_MUTATE_ROOT then owner.root_entry_generation = owner.root_entry_generation + 1 end
      if _G.TEST_BOOLEAN_MUTATE_STABLE then
        state.stable_acquisition_generation = state.stable_acquisition_generation + 1
      end
      if _G.TEST_BOOLEAN_MUTATE_PACK_GUARDS then
        _G.TEST_BOOLEAN_MUTATE_PACK_GUARDS["mutated-pack"] = true
      end
      if _G.TEST_BOOLEAN_MUTATE_RECIPE_EPOCH then
        context.epochs.recipe_index = context.epochs.recipe_index + 1
      end
      if _G.TEST_BOOLEAN_MUTATE_SOURCE then
        _G.TEST_BOOLEAN_SOURCE_EPOCH = "boolean-epoch-b"
      end
      if _G.TEST_BOOLEAN_RETURN_FALSE then return nil end
      return _G.TEST_BOOLEAN_WITNESS
    end
  }
end
'''


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    source = (repo / SOURCE_PATH).read_text(encoding="utf-8")
    fixture = (repo / FIXTURE_PATH).read_text(encoding="utf-8")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(BOOTSTRAP)
    module = runtime.execute(source)
    runtime.globals().CONTEXTUAL_BOOLEAN_ACQUISITION_MODULE = module
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-CONTEXTUAL-BOOLEAN-ACQUISITION-MEMO-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "acquisition_calls": int(result["calls"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
