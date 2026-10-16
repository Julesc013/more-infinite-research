#!/usr/bin/env python3
"""Exercise the ProviderMetrics lazy-inspection seam without Factorio."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


RESOLVER = Path("source/prototypes/mir/families/resolver.lua")
CONTEXT = Path("source/prototypes/mir/pipeline/compiler_orchestrator/context_construction.lua")
PUBLICATION = Path("source/prototypes/mir/pipeline/compiler_orchestrator/publication.lua")
FINGERPRINT = Path("source/prototypes/mir/core/fingerprint.lua")
PROVIDER_METRICS = Path("source/prototypes/mir/providers/provider_metrics.lua")
FIXTURE = Path("tests/compiler/provider_metrics_lazy.lua")


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

    resolver_source = (repo / RESOLVER).read_text(encoding="utf-8")
    context_source = (repo / CONTEXT).read_text(encoding="utf-8")
    publication_source = (repo / PUBLICATION).read_text(encoding="utf-8")
    fingerprint_source = (repo / FINGERPRINT).read_text(encoding="utf-8")
    provider_metrics_source = (repo / PROVIDER_METRICS).read_text(encoding="utf-8")
    fixture_source = (repo / FIXTURE).read_text(encoding="utf-8")
    for needle, source, name in (
        ("family_resolver.compilation_projection()", context_source, "compiler context"),
        ("family_resolver.inspection_snapshot()", publication_source, "publication"),
        ("if include_internal and publishes_mod_data then", publication_source, "publication gate"),
    ):
        if needle not in source:
            raise RuntimeError(f"ProviderMetrics lazy boundary is missing {needle!r} from {name}")

    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        r'''
local function graph_copy(value, copied)
  if type(value) ~= "table" then return value end
  copied = copied or {}
  if copied[value] then return copied[value] end
  local out = {}
  copied[value] = out
  for key, member in pairs(value) do out[graph_copy(key, copied)] = graph_copy(member, copied) end
  return out
end

local function canonical(value, seen)
  local kind = type(value)
  if kind == "nil" then return "nil" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  assert(kind == "table", "unsupported test fingerprint type: " .. kind)
  seen = seen or {}
  assert(not seen[value], "cyclic test fingerprint")
  seen[value] = true
  local keys = {}
  for key in pairs(value) do table.insert(keys, key) end
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  local out = {"{"}
  for _, key in ipairs(keys) do table.insert(out, canonical(key, seen) .. ":" .. canonical(value[key], seen) .. ";") end
  table.insert(out, "}")
  seen[value] = nil
  return table.concat(out)
end

TEST_PROVIDER_CONTEXT = {states = {}}
function TEST_PROVIDER_CONTEXT:state_view(name, factory)
  if self.states[name] == nil and factory then self.states[name] = factory() end
  return self.states[name]
end
function TEST_PROVIDER_CONTEXT:set_state(name, value)
  assert(self.states[name] == nil, "duplicate state: " .. name)
  self.states[name] = value
  return value
end
function TEST_PROVIDER_CONTEXT:replace_epoch(name, value)
  self.states[name] = value
  return value
end
function TEST_PROVIDER_CONTEXT:state_epoch(_) return 1 end
TEST_PROVIDER_EPOCH = 1
TEST_PROVIDER_METRIC_BUILDS = 0
TEST_PROVIDER_RULE = {id = "family-a", provider_id = "provider-a", schema = 2,
  grouping = {stream = "research_auto_productivity"}, cardinality = {maximum_candidates = 1}}
TEST_PROVIDER_LAST_RULE = {id = "family-b", provider_id = "provider-a", schema = 2,
  grouping = {stream = "research_auto_productivity"}, cardinality = {maximum_candidates = 1}}

package.preload["prototypes.mir.core.deepcopy"] = function() return graph_copy end
package.preload["prototypes.mir.index.relationships"] = function() return {view = function() return {} end} end
package.preload["prototypes.mir.families.registry"] = function()
  return {view = function() return {rules = {TEST_PROVIDER_RULE, TEST_PROVIDER_LAST_RULE}} end}
end
package.preload["prototypes.mir.compatibility.policy_authority"] = function()
  return {candidate_seeds = function() return {} end, blocker_is_reviewable = function() return false end}
end
package.preload["prototypes.mir.pipeline.compiler_context"] = function()
  return {current = function() return TEST_PROVIDER_CONTEXT end}
end
package.preload["prototypes.mir.families.operator_dsl"] = function()
  return {grouping_stream = function(grouping) return grouping and grouping.stream or "research_auto_productivity" end,
    effect_change = function() return 1 end, grouping_action = function() return "attach" end}
end
package.preload["prototypes.mir.report.compiler_telemetry"] = function()
  return {start_phase = function() end, finish_phase = function() end, count = function() end}
end
package.preload["prototypes.mir.providers.pipeline.discovery"] = function()
  return {candidates = function() return {
    {recipe = "recipe-z", item = "item-z"}, {recipe = "recipe-a", item = "item-a"}
  } end}
end
package.preload["prototypes.mir.providers.pipeline.normalization"] = function() return {candidate = function(value) return value end} end
package.preload["prototypes.mir.providers.pipeline.classification"] = function()
  return {evaluate = function() return {eligible = true, risk_disposition = "NONE"} end}
end
package.preload["prototypes.mir.providers.pipeline.pack_policy"] = function() return {resolve = function() return {} end} end
package.preload["prototypes.mir.providers.pipeline.hazard_policy"] = function()
  return {resolve = function() return {eligible = true, risk_disposition = "NONE"} end}
end
package.preload["prototypes.mir.providers.pipeline.owner_arbitration"] = function() return {blocker = function() return nil end} end
package.preload["prototypes.mir.providers.pipeline.decision"] = function()
  return {build = function(rule, stream, candidate, classified, _, change, action, depth)
    return {rule = rule.id, provider_id = rule.provider_id, provider_version = "fixture", candidate_family = rule.id,
      recipe = candidate.recipe, item = candidate.item, target_stream = stream, change = change, decision = action,
      final_state = action == "attach" and "attach" or "diagnose", risk_disposition = classified.risk_disposition,
      claim_fingerprint = "claim-a", decision_fingerprint = "decision-a", risk_fingerprint = "risk-a",
      earliest_unlock_depth = depth}
  end, refresh_fingerprint = function(row) row.decision_fingerprint = "refreshed" end}
end
package.preload["prototypes.mir.providers.pipeline.provider_claim"] = function()
  return {arbitrate = function(claims) return {status = "PASS", attachment = claims[1]} end}
end
package.preload["prototypes.mir.providers.pipeline.budget"] = function()
  return {apply = function(rows) return {status = "PASS", cardinality_fingerprint = "budget:" .. tostring(#rows)} end}
end
package.preload["prototypes.mir.graph.researchability_index"] = function()
  return {build = function() return {unlock_depths = {automation = 1}} end}
end
package.preload["prototypes.mir.index.recipe_facts"] = function() return {source_epoch = function() return TEST_PROVIDER_EPOCH end} end
package.preload["prototypes.mir.index.recipe_unlocks"] = function()
  return {for_recipe = function()
    if TEST_PROVIDER_CONTEXT.states.recipe_unlock_index == nil then
      TEST_PROVIDER_CONTEXT:set_state("recipe_unlock_index", {
        recipe_source_epoch = TEST_PROVIDER_EPOCH, unlockers_by_recipe = { ["recipe-a"] = {"automation"} }
      })
    end
    return {"automation"}
  end}
end
package.preload["prototypes.mir.platform.factorio.environment_identity"] = function()
  return {current = function() return {trusted = true, environment_fingerprint = "environment-a"} end}
end
package.preload["prototypes.mir.domain.environment_identity"] = function()
  return {assert_trusted = function(value) assert(value.trusted == true, "untrusted environment") end}
end
'''
    )
    fingerprint = runtime.execute(fingerprint_source)
    runtime.globals().PROVIDER_METRICS_LAZY_FINGERPRINT = fingerprint
    runtime.execute(
        'package.preload["prototypes.mir.core.fingerprint"] = function() '
        'return PROVIDER_METRICS_LAZY_FINGERPRINT end'
    )
    provider_metrics = runtime.execute(provider_metrics_source)
    runtime.globals().PROVIDER_METRICS_LAZY_REAL_METRICS = provider_metrics
    runtime.execute(
        '''package.preload["prototypes.mir.providers.provider_metrics"] = function()
  local raw = PROVIDER_METRICS_LAZY_REAL_METRICS
  return {build = function(...)
    TEST_PROVIDER_METRIC_BUILDS = TEST_PROVIDER_METRIC_BUILDS + 1
    return raw.build(...)
  end}
end'''
    )
    module = runtime.execute(resolver_source)
    runtime.globals().PROVIDER_METRICS_LAZY_RESOLVER = module
    result = runtime.execute(fixture_source)
    record = {
        "status": "MIR-PROVIDER-METRICS-LAZY-CONTROLS-PASSED",
        "scope": "host-only-provider-metrics-boundary",
        "assertions": int(result["assertions"]),
        "metric_builds": int(result["metric_builds"]),
        "resolver_sha256": hashlib.sha256(resolver_source.encode("utf-8")).hexdigest(),
        "context_sha256": hashlib.sha256(context_source.encode("utf-8")).hexdigest(),
        "publication_sha256": hashlib.sha256(publication_source.encode("utf-8")).hexdigest(),
        "fingerprint_sha256": hashlib.sha256(fingerprint_source.encode("utf-8")).hexdigest(),
        "provider_metrics_sha256": hashlib.sha256(provider_metrics_source.encode("utf-8")).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture_source.encode("utf-8")).hexdigest(),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
