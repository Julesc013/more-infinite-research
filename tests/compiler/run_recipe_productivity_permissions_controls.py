#!/usr/bin/env python3
"""Exercise the canonical implicit-only productivity permission gate without Factorio."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


PIPELINE = Path("source/prototypes/mir/pipeline/recipe_productivity_permissions.lua")
STREAMS = Path("source/prototypes/streams/productivity.lua")
DESCRIPTOR = Path("source/prototypes/mir/domain/streams/descriptor.lua")
FIXTURE = Path("tests/compiler/recipe_productivity_permissions.lua")
SEMANTICS = Path("source/prototypes/mir/domain/facts/recipe_semantics.lua")
MATCHER = Path("source/prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua")
PLANNER = Path("source/prototypes/mir/capabilities/recipe_productivity/planner.lua")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--lua-runtime-dir", required=True)
    args = parser.parse_args()
    repo = Path(args.repo_root).resolve()
    runtime_dir = Path(args.lua_runtime_dir).resolve()
    if not runtime_dir.is_dir():
        raise RuntimeError(f"Lua runtime directory is unavailable: {runtime_dir}")
    sys.path.insert(0, str(runtime_dir))
    from lupa import lua52

    source = (repo / PIPELINE).read_text(encoding="utf-8")
    streams = (repo / STREAMS).read_text(encoding="utf-8")
    descriptor = (repo / DESCRIPTOR).read_text(encoding="utf-8")
    fixture = (repo / FIXTURE).read_text(encoding="utf-8")
    semantics_source = (repo / SEMANTICS).read_text(encoding="utf-8")
    matcher_source = (repo / MATCHER).read_text(encoding="utf-8")
    planner_source = (repo / PLANNER).read_text(encoding="utf-8")
    for required in (
        '{name = "burner-mining-drill", required_mods = {"base"}, only_if_implicit_productivity = true}',
        '{name = "electric-mining-drill", required_mods = {"base"}, only_if_implicit_productivity = true}',
        '{name = "big-mining-drill", required_mods = {"space-age"}, only_if_implicit_productivity = true}',
        '{name = "se-core-miner-drill", required_mods = {"space-exploration"}, only_if_implicit_productivity = true}',
        '{ change = 0.20, items = { "burner-mining-drill" }, reject_explicit_productivity_denial = true }',
        '{ change = 0.10, items = { "electric-mining-drill" }, reject_explicit_productivity_denial = true }',
        '{ change = 0.05, items = { "big-mining-drill" }, reject_explicit_productivity_denial = true, item_patterns = {',
    ):
        if required not in streams:
            raise RuntimeError(f"Mining stream is missing required implicit-only permission: {required}")
    if 'permission.only_if_implicit_productivity' not in descriptor:
        raise RuntimeError("Stream descriptor does not validate the implicit-only permission field")

    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(
        """
package.preload["prototypes.mir.platform.factorio.data_raw"] = function()
  return {prototypes = function(kind)
    if kind == "recipe" then return _G.data.raw.recipe end
    return {}
  end}
end
package.preload["prototypes.mir.platform.factorio.mods"] = function()
  return {all_exist = function(names)
    for _, name in ipairs(names or {}) do if _G.mods[name] == nil then return false end end
    return true
  end}
end
package.preload["prototypes.mir.settings.resolver"] = function()
  return {stream_enabled = function(key)
    return _G.MIR_ENABLED_STREAMS == nil or _G.MIR_ENABLED_STREAMS[key] ~= false
  end}
end
package.preload["prototypes.mir.streams.registry"] = function()
  return {
    view = function() return _G.MIR_PERMISSION_STREAMS end,
    sorted_keys = function()
      local keys = {}
      for key in pairs(_G.MIR_PERMISSION_STREAMS) do table.insert(keys, key) end
      table.sort(keys)
      return keys
    end
  }
end
"""
    )
    module = runtime.execute(source)
    runtime.globals().MIR_RECIPE_PRODUCTIVITY_PERMISSIONS = module
    result = runtime.execute(fixture)

    descriptor_runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    descriptor_runtime.execute(
        """
package.preload["prototypes.mir.core.deepcopy"] = function()
  local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, nested in pairs(value) do out[copy(key)] = copy(nested) end; return out
  end
  return copy
end
package.preload["prototypes.mir.domain.effects.metadata"] = function() return {numeric_descriptor = function() return nil end} end
package.preload["prototypes.mir.domain.technology.technology_risk"] = function() return {normalize = function(value) return value end} end
"""
    )
    descriptor_module = descriptor_runtime.execute(descriptor)
    invalid_descriptor = descriptor_runtime.eval(
        "function(descriptor) return pcall(descriptor.normalize, 'research_mining_drill', {"
        "productivity_permission_recipes = {{name='drill', required_mods={'base'}, only_if_implicit_productivity='yes'}}, groups={{change=0.05}}}) end"
    )(descriptor_module)
    if invalid_descriptor[0]:
        raise RuntimeError("Descriptor accepted a non-boolean implicit-only productivity permission")

    runtime.execute(
        """
local registry = package.loaded["prototypes.mir.streams.registry"]
registry.shared = {per_level_default = 0.10}
package.preload["prototypes.mir.platform.factorio.prototype_lookup"] = function()
  return {each_item_prototype=function() end, each_fluid_prototype=function() end}
end
package.preload["prototypes.mir.domain.facts.recipe_semantics"] = function() return _G.MIR_RECIPE_SEMANTICS end
package.preload["prototypes.mir.index.recipe_facts"] = function()
  return {
    candidate_names = function() local out={}; for name in pairs(_G.MIR_MATCH_FACTS) do out[#out+1]=name end; table.sort(out); return out end,
    view = function(name) return _G.MIR_MATCH_FACTS[name] end,
    fingerprint = function() return "permission-matcher-fixture" end,
    for_each = function(callback) for name, fact in pairs(_G.MIR_MATCH_FACTS) do callback(name, fact) end end
  }
end
package.preload["prototypes.mir.index.recipe_risk_facts"] = function() return {view=function() return nil end} end
package.preload["prototypes.mir.index.item_prototype_facts"] = function() return {module_items=function() return {} end,placeable_items_for_entity_types=function() return {} end,for_each_spoilage=function() end,for_each_fuel_burning=function() end} end
package.preload["prototypes.mir.core.deepcopy"] = function() return function(value) return value end end
package.preload["prototypes.mir.core.fingerprint"] = function() return {of=function() return "permission-matcher-fixture" end} end
package.preload["prototypes.mir.platform.factorio.target_profiles"] = function() return {current=function() return {prototype_shapes={recipe_property_defaults={allow_productivity=false,allow_quality=true,maximum_productivity=3.0}}} end} end
package.preload["prototypes.mir.report.compiler_telemetry"] = function() return {count=function() end,observe_max=function() end} end
package.preload["prototypes.mir.pipeline.compiler_context"] = function() return {current=function() return {state_view=function(_, _, factory) return factory() end} end} end
package.preload["prototypes.mir.settings.automatic_compiler_policy"] = function() return {current=function() return {apply_changes=true} end} end
package.preload["prototypes.mir.index.relationships"] = function() return {view=function() return {} end} end
package.preload["prototypes.mir.platform.factorio.data_raw"] = function() return {technology=function() return nil end} end
package.preload["prototypes.mir.domain.facts.generated_technology_registry"] = function() return {is_stream=function() return false end} end
package.preload["prototypes.mir.report.diagnostics_sink"] = function() return {enabled=function() return false end,material_route_certificate=function() end,recipe_matches=function() end,record_recipe_match=function() end} end
"""
    )
    runtime.globals().MIR_RECIPE_SEMANTICS = runtime.execute(semantics_source)
    runtime.globals().MIR_RECIPE_MATCHER = runtime.execute(matcher_source)
    runtime.execute('package.loaded["prototypes.mir.capabilities.recipe_productivity.recipe_matching"] = _G.MIR_RECIPE_MATCHER')
    runtime.globals().MIR_RECIPE_PRODUCTIVITY_PLANNER = runtime.execute(planner_source)
    pipeline_assertions = runtime.execute(
        """
local semantics = _G.MIR_RECIPE_SEMANTICS
local matcher = _G.MIR_RECIPE_MATCHER
local planner = _G.MIR_RECIPE_PRODUCTIVITY_PLANNER
local permissions = _G.MIR_RECIPE_PRODUCTIVITY_PERMISSIONS
local profile = {prototype_shapes={recipe_property_defaults={allow_productivity=false,allow_quality=true,maximum_productivity=3.0}}}
local assertions = 0
local function check(value, message) assert(value, message); assertions = assertions + 1 end
local function fact(name, recipe)
  local resolved = semantics.resolve(recipe, recipe, profile)
  return {
    name=name, hidden=false, source_class="ordinary", parameter=false,
    productive_result_names={name}, ingredient_names={"iron-plate"},
    variants={{ingredients={{type="item",name="iron-plate",amount=1}}, results={{type="item",name=name,amount=1}},
      effective_allow_productivity=resolved.effective_allow_productivity,
      declared_allow_productivity=resolved.declared_allow_productivity,
      declared_maximum_productivity=resolved.declared_maximum_productivity,
      effective_maximum_productivity=resolved.effective_maximum_productivity}},
    effective_allow_productivity=resolved.effective_allow_productivity,
    declared_allow_productivity=resolved.declared_allow_productivity,
    declared_maximum_productivity=resolved.declared_maximum_productivity,
    effective_maximum_productivity=resolved.effective_maximum_productivity,
    allow_productivity=resolved.effective_allow_productivity
  }
end
local function materialize(name, recipe, enabled)
  _G.mods={base="2.1.21",["space-age"]="2.1.21"}
  _G.data={raw={recipe={[name]=recipe}}}
  _G.MIR_ENABLED_STREAMS={research_mining_drill=enabled}
  _G.MIR_PERMISSION_STREAMS={research_mining_drill={productivity_permission_recipes={{name=name,required_mods={"space-age"},only_if_implicit_productivity=true}}}}
  permissions.apply()
  _G.MIR_MATCH_FACTS={[name]=fact(name, recipe)}
  local buckets=matcher.recipes_for_stream({groups={{change=0.05,items={name},reject_explicit_productivity_denial=true}}},0.10)
  return recipe, planner.effects_from_buckets("research_mining_drill",buckets)
end
local enabled, effects = materialize("big-mining-drill", {}, true)
check(enabled.allow_productivity == true, "actual permission pipeline grants an implicit recipe before matching")
check(#effects == 1 and effects[1].type == "change-recipe-productivity" and effects[1].recipe == "big-mining-drill" and effects[1].change == 0.05,
  "actual matcher buckets feed the existing productivity-effect emitter with the declared 5 percent drill effect")
local denied, denied_effects = materialize("big-mining-drill", {allow_productivity=false}, true)
check(denied.allow_productivity == false and #denied_effects == 0,
  "explicit productivity denials stay byte-for-value false and produce no drill effect")
local capped, capped_effects = materialize("big-mining-drill", {maximum_productivity=0}, true)
check(capped.maximum_productivity == 0 and #capped_effects == 0,
  "an explicit zero cap stays byte-for-value zero and produces no drill effect")
_G.mods={base="2.1.21",["space-age"]="2.1.21"}
_G.data={raw={recipe={["big-mining-drill"]={}}}}
_G.MIR_ENABLED_STREAMS={research_mining_drill=false}
_G.MIR_PERMISSION_STREAMS={research_mining_drill={productivity_permission_recipes={{name="big-mining-drill",required_mods={"space-age"},only_if_implicit_productivity=true}}}}
permissions.apply()
check(_G.data.raw.recipe["big-mining-drill"].allow_productivity == nil,
  "a disabled stream leaves the implicit recipe unmutated before the normal planner skips that stream")
return assertions
"""
    )
    if int(pipeline_assertions) != 5:
        raise RuntimeError(f"Unexpected actual permission-to-effect assertion count: {pipeline_assertions}")
    record = {
        "status": "MIR-RECIPE-PRODUCTIVITY-PERMISSIONS-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "pipeline_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "streams_sha256": hashlib.sha256(streams.encode()).hexdigest(),
        "descriptor_sha256": hashlib.sha256(descriptor.encode()).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode()).hexdigest(),
        "semantics_sha256": hashlib.sha256(semantics_source.encode()).hexdigest(),
        "matcher_sha256": hashlib.sha256(matcher_source.encode()).hexdigest(),
        "planner_sha256": hashlib.sha256(planner_source.encode()).hexdigest(),
        "descriptor_assertions": 1,
        "pipeline_assertions": int(pipeline_assertions),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
