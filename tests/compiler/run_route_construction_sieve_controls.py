#!/usr/bin/env python3
"""Run source-bound Lua controls for the disabled production-route sieve.

The controls execute no Factorio process and write no package or fixture. They
load the exact product helper with an isolated, minimal structural context and
compare it with the actual selection policy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


SOURCE_PATH = Path("tests/reference/retired-discovery/prototypes/mir/capabilities/science_integration/pack_production_reachability.lua")
POLICY_PATH = Path("tests/reference/retired-discovery/prototypes/mir/capabilities/science_integration/production_route_policy.lua")
FIXTURE_PATH = Path("tests/compiler/route_construction_sieve.lua")
RETURN_MARKER = "\nreturn M"


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    return parser.parse_args()


def instrument(source: str) -> str:
    position = source.rfind(RETURN_MARKER)
    if position < 0 or source[position + len(RETURN_MARKER) :].strip():
        raise RuntimeError("Expected the canonical reachability module to end with exactly return M")
    hooks = """
M.__mir_route_construction_sieve_test_hooks = {
  route_gate_set = route_gate_set,
  disabled_producer_cannot_win = disabled_producer_cannot_win,
  static_unlock_facts = static_unlock_facts
}
return M
"""
    return source[:position] + "\n" + hooks


def lua_string(value: str) -> str:
    """JSON strings are valid quoted string literals in the target Lua subset."""
    return json.dumps(value)


def main() -> int:
    args = arguments()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52  # Local checked-in runtime only; no dependency installation.

    source = (repo / SOURCE_PATH).read_text(encoding="utf-8")
    policy = (repo / POLICY_PATH).read_text(encoding="utf-8")
    fixture = (repo / FIXTURE_PATH).read_text(encoding="utf-8")
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[copy(key)] = copy(item) end
  return out
end

local context = {states = {}, epochs = {technology_researchability_index = 1}}
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
function context:replace_epoch(name, value, expected)
  if expected ~= nil and self.epochs[name] ~= expected then error("unexpected fixture epoch") end
  self.states[name] = value
  self.epochs[name] = (self.epochs[name] or 0) + 1
  return value
end
function context:state_epoch(name) return self.epochs[name] end
function context:service(_) return nil end

local test_index = {
  index_fingerprint = "route-construction-sieve-index",
  structural_failures = {T = false, U = false, V = false, P = false, Q = false, bad = "missing"},
  unlock_depths = {T = 1, U = 1, V = 1, P = 0, Q = 0},
  closures = {
    T = {"P", "T"}, U = {"Q", "U"}, V = {"P", "V"},
    P = {"P"}, Q = {"Q"}, bad = {"bad"}
  }
}
context.states.technology_researchability_index = test_index

local recipe_unlockers = {
  ["disabled-strict"] = {"T"},
  ["multi-escape"] = {"T", "U"},
  ["multi-dominated"] = {"T", "V"},
  ["z-equal"] = {"T"},
  ["a-earlier"] = {"T"},
  ["no-unlocker"] = {},
  ["structural-unknown"] = {"bad"}
}

package.preload["prototypes.mir.core.deepcopy"] = function() return copy end
package.preload["prototypes.mir.capabilities.science_integration.pack_registry"] = function() return {} end
package.preload["prototypes.mir.capabilities.science_integration.recipe_unlock_facts"] = function()
  return {unlockers_for_recipe = function(name) return copy(recipe_unlockers[name] or {}) end}
end
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {source_epoch = function() return 1 end}
end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function()
  return {technology = function(name) return {name = name, unit = {ingredients = {}}} end}
end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return context end}
end
package.preload["prototypes.mir.graph.researchability_index"] = function()
  return {
    build = function() return test_index end,
    reachable_names = function(index, name) return copy(index.closures[name] or {name}) end
  }
end
package.preload["prototypes.mir.capabilities.science_integration.technology_researchability"] = function()
  return {reason_with_context = function() return nil end}
end
package.preload["prototypes.mir.capabilities.science_integration.recipe_route_feasibility"] = function()
  return {}
end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {count = function() end, observe_max = function() end}
end
"""
    )
    runtime.execute(
        "package.preload[\"prototypes.mir.capabilities.science_integration.production_route_policy\"] = "
        "function() return assert(load(" + lua_string(policy) + ", \"@production_route_policy.lua\"))() end"
    )
    module = runtime.execute(instrument(source))
    runtime.globals().ROUTE_CONSTRUCTION_SIEVE_HOOKS = module[
        "__mir_route_construction_sieve_test_hooks"
    ]
    runtime.globals().ROUTE_CONSTRUCTION_SIEVE_POLICY = runtime.eval(
        "require('prototypes.mir.capabilities.science_integration.production_route_policy')"
    )
    result = runtime.execute(fixture)
    record = {
        "status": "MIR-ROUTE-CONSTRUCTION-SIEVE-CONTROLS-PASSED",
        "scope": "retired-discovery-characterization-not-current-package-certification",
        "assertions": int(result["assertions"]),
        "source_sha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "policy_sha256": hashlib.sha256(policy.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
