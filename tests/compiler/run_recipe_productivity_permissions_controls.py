#!/usr/bin/env python3
"""Exercise the canonical implicit-only productivity permission gate without Factorio."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


PIPELINE = Path("source/prototypes/mir/pipeline/recipe_productivity_permissions.lua")
STREAMS = Path("source/prototypes/streams/productivity.lua")
DESCRIPTOR = Path("source/prototypes/mir/domain/streams/descriptor.lua")
FIXTURE = Path("tests/compiler/recipe_productivity_permissions.lua")
SEMANTICS = Path("source/prototypes/mir/domain/facts/recipe_semantics.lua")
MATCHER = Path("source/prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua")
PLANNER = Path("source/prototypes/mir/capabilities/recipe_productivity/planner.lua")
PUBLISHED_PRODUCTIVITY = "source/prototypes/streams/productivity.lua"
PUBLISHED_MINING_GROUPS = (
    '{ change = 0.20, items = { "burner-mining-drill" } },',
    '{ change = 0.10, items = { "electric-mining-drill" } },',
    '{ change = 0.05, items = { "big-mining-drill" }, item_patterns = {',
)


def stream_block(source: str, key: str, next_key: str, origin: str) -> str:
    start = source.find(f'  {key} = {{')
    end = source.find(f'\n\n  {next_key} = {{', start)
    if start < 0 or end < 0:
        raise RuntimeError(f"Stream {key} is unavailable in {origin}")
    return source[start:end]


def mining_stream_block(source: str, origin: str) -> str:
    return stream_block(source, "research_mining_drill", "research_electric_energy", origin)


def git_output(repo: Path, args: list[str], description: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(f"{description} is unavailable: {result.stderr.strip()}")
    return result.stdout


def published_productivity(repo: Path, tag: str) -> tuple[str, dict[str, str]]:
    source = git_output(
        repo,
        ["show", f"{tag}:{PUBLISHED_PRODUCTIVITY}"],
        f"Published mining baseline {tag}",
    )
    return source, {
        "tag": tag,
        "commit": git_output(repo, ["rev-list", "-n", "1", tag], f"Published tag {tag}").strip(),
        "blob": git_output(
            repo,
            ["rev-parse", f"{tag}:{PUBLISHED_PRODUCTIVITY}"],
            f"Published productivity blob {tag}",
        ).strip(),
        "sha256": hashlib.sha256(source.encode()).hexdigest(),
    }


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
    published_baseline_assertions = 0
    published_baselines: dict[str, dict[str, str]] = {}
    published_mining_blocks: dict[str, str] = {}
    published_capture_blocks: dict[str, str] = {}
    published_platform_blocks: dict[str, str] = {}
    for tag in ("v4.2.2", "v4.3.0"):
        published_source, published_identity = published_productivity(repo, tag)
        published_block = mining_stream_block(published_source, tag)
        published_baselines[tag] = published_identity
        published_mining_blocks[tag] = published_block
        published_capture_blocks[tag] = stream_block(
            published_source, "research_capture_robot_rockets", "research_grenades", tag
        )
        published_platform_blocks[tag] = stream_block(
            published_source, "research_platform", "research_artificial_soil", tag
        )
        if "reject_explicit_productivity_denial" in published_block:
            raise RuntimeError(f"Published mining baseline {tag} unexpectedly rejects explicit recipe productivity declarations")
        if "productivity_permission_recipes" in published_block:
            raise RuntimeError(f"Published mining baseline {tag} unexpectedly grants drill productivity permissions")
        published_baseline_assertions += 1
        for group in PUBLISHED_MINING_GROUPS:
            if group not in published_block:
                raise RuntimeError(f"Published mining baseline {tag} is missing its declared group: {group}")
            published_baseline_assertions += 1
    current_mining_block = mining_stream_block(streams, str(STREAMS))
    if "reject_explicit_productivity_denial" in current_mining_block:
        raise RuntimeError(
            "Current mining-drill stream changes the published explicit-productivity emission contract"
        )
    published_baseline_assertions += 1
    if "productivity_permission_recipes" in current_mining_block:
        raise RuntimeError(
            "Current mining-drill stream adds an unsupported productivity permission"
        )
    published_baseline_assertions += 1
    if "only_if_implicit_productivity" in streams or "only_if_implicit_productivity" in source or "only_if_implicit_productivity" in descriptor:
        raise RuntimeError("Current productivity permission pipeline retains unsupported implicit-only drill admission")
    published_baseline_assertions += 1
    for group in PUBLISHED_MINING_GROUPS:
        if group not in current_mining_block:
            raise RuntimeError(f"Current mining-drill stream no longer retains its published group: {group}")
        published_baseline_assertions += 1
    runtime = lua52.LuaRuntime(unpack_returned_tuples=True)
    def parse_stream(block: str, key: str):
        return runtime.execute(
            "local function space_age_setting_visibility() return {} end\nreturn {\n" + block + "\n}"
        )[key]

    current_mining_spec = parse_stream(current_mining_block, "research_mining_drill")
    current_capture_spec = parse_stream(
        stream_block(streams, "research_capture_robot_rockets", "research_grenades", str(STREAMS)),
        "research_capture_robot_rockets",
    )
    current_platform_spec = parse_stream(
        stream_block(streams, "research_platform", "research_artificial_soil", str(STREAMS)),
        "research_platform",
    )
    published_422_mining = parse_stream(published_mining_blocks["v4.2.2"], "research_mining_drill")
    published_430_mining = parse_stream(published_mining_blocks["v4.3.0"], "research_mining_drill")
    published_422_capture = parse_stream(published_capture_blocks["v4.2.2"], "research_capture_robot_rockets")
    published_430_capture = parse_stream(published_capture_blocks["v4.3.0"], "research_capture_robot_rockets")
    published_422_platform = parse_stream(published_platform_blocks["v4.2.2"], "research_platform")
    published_430_platform = parse_stream(published_platform_blocks["v4.3.0"], "research_platform")
    current_mining_groups = current_mining_spec["groups"]
    published_422_groups = published_422_mining["groups"]
    published_430_groups = published_430_mining["groups"]
    runtime.globals().MIR_CURRENT_MINING_GROUPS = current_mining_groups
    runtime.globals().MIR_CURRENT_MINING_SPEC = current_mining_spec
    runtime.globals().MIR_CURRENT_CAPTURE_SPEC = current_capture_spec
    runtime.globals().MIR_CURRENT_PLATFORM_SPEC = current_platform_spec
    runtime.globals().MIR_PUBLISHED_422_MINING_GROUPS = published_422_groups
    runtime.globals().MIR_PUBLISHED_430_MINING_GROUPS = published_430_groups
    runtime.globals().MIR_PUBLISHED_422_CAPTURE_SPEC = published_422_capture
    runtime.globals().MIR_PUBLISHED_430_CAPTURE_SPEC = published_430_capture
    runtime.globals().MIR_PUBLISHED_422_PLATFORM_SPEC = published_422_platform
    runtime.globals().MIR_PUBLISHED_430_PLATFORM_SPEC = published_430_platform
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

    runtime.execute(
        """
local registry = package.loaded["prototypes.mir.streams.registry"]
registry.shared = {per_level_default = 0.10}
package.preload["prototypes.mir.platform.factorio.prototype_lookup"] = function()
  return {
    each_item_prototype=function(callback)
      for name, prototype in pairs(_G.MIR_ITEM_PROTOTYPES or {}) do callback(name, prototype, "item") end
    end,
    each_fluid_prototype=function() end
  }
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
local legacy_recipes = {
  ["burner-mining-drill"]={allow_productivity=false},
  ["electric-mining-drill"]={normal={allow_productivity=false}},
  ["big-mining-drill"]={maximum_productivity=0},
  ["se-core-miner-drill"]={expensive={maximum_productivity=0}}
}
_G.MIR_MATCH_FACTS={}
_G.MIR_ITEM_PROTOTYPES={
  ["burner-mining-drill"]={}, ["electric-mining-drill"]={},
  ["big-mining-drill"]={}, ["se-core-miner-drill"]={}
}
for name, recipe in pairs(legacy_recipes) do _G.MIR_MATCH_FACTS[name]=fact(name,recipe) end
local function normalized_groups(groups)
  local rows = {}
  for ordinal, group in ipairs(groups) do
    rows[#rows + 1] = table.concat({
      ordinal, group.change, table.concat(group.items or {}, ","),
      table.concat(group.item_patterns or {}, ","), tostring(group.reject_explicit_productivity_denial)
    }, "|")
  end
  return table.concat(rows, ";")
end
local function permission_shape(spec)
  local rows = {}
  for _, permission in ipairs(spec.productivity_permission_recipes or {}) do
    rows[#rows + 1] = permission.name .. "|" .. table.concat(permission.required_mods or {}, ",")
  end
  return table.concat(rows, ";")
end
local published_422_effects = planner.effects_from_buckets("research_mining_drill",matcher.recipes_for_stream({groups=_G.MIR_PUBLISHED_422_MINING_GROUPS},0.10))
local published_430_effects = planner.effects_from_buckets("research_mining_drill",matcher.recipes_for_stream({groups=_G.MIR_PUBLISHED_430_MINING_GROUPS},0.10))
local current_effects = planner.effects_from_buckets("research_mining_drill",matcher.recipes_for_stream({groups=_G.MIR_CURRENT_MINING_GROUPS},0.10))
check(normalized_groups(_G.MIR_PUBLISHED_422_MINING_GROUPS) == normalized_groups(_G.MIR_PUBLISHED_430_MINING_GROUPS),
  "published 4.2.2 and 4.3.0 mining groups agree on exact membership, changes, patterns, and denial policy")
check(normalized_groups(_G.MIR_CURRENT_MINING_GROUPS) == normalized_groups(_G.MIR_PUBLISHED_430_MINING_GROUPS),
  "current parsed mining groups preserve the published explicit-productivity emission contract")
check(permission_shape(_G.MIR_CURRENT_CAPTURE_SPEC) == permission_shape(_G.MIR_PUBLISHED_422_CAPTURE_SPEC)
    and permission_shape(_G.MIR_CURRENT_CAPTURE_SPEC) == permission_shape(_G.MIR_PUBLISHED_430_CAPTURE_SPEC),
  "current capture-robot Space Age permission remains exactly published")
check(permission_shape(_G.MIR_CURRENT_PLATFORM_SPEC) == permission_shape(_G.MIR_PUBLISHED_422_PLATFORM_SPEC)
    and permission_shape(_G.MIR_CURRENT_PLATFORM_SPEC) == permission_shape(_G.MIR_PUBLISHED_430_PLATFORM_SPEC),
  "current platform Space Age permission rows remain exactly published")
check(#current_effects == #published_422_effects and #current_effects == #published_430_effects,
  "current parsed mining groups retain all published native and Space Exploration drill effects")
local expected_changes={
  ["burner-mining-drill"]=0.20, ["electric-mining-drill"]=0.10,
  ["big-mining-drill"]=0.05, ["se-core-miner-drill"]=0.05
}
local emitted={}
local published_422_emitted, published_430_emitted = {}, {}
for _, effect in ipairs(current_effects) do emitted[effect.recipe]=effect.change end
for _, effect in ipairs(published_422_effects) do published_422_emitted[effect.recipe]=effect.change end
for _, effect in ipairs(published_430_effects) do published_430_emitted[effect.recipe]=effect.change end
for recipe, change in pairs(expected_changes) do
  check(emitted[recipe] == change, "published mining emission retains the exact drill effect: " .. recipe)
  check(published_422_emitted[recipe] == change and published_430_emitted[recipe] == change,
    "published baseline mining emission remains independently pinned: " .. recipe)
end
check(emitted["iron-ore"] == nil and emitted["copper-ore"] == nil,
  "published mining productivity effects target drill recipes and never ore yield")
return assertions
"""
    )
    if int(pipeline_assertions) != 14:
        raise RuntimeError(f"Unexpected actual permission-to-effect assertion count: {pipeline_assertions}")
    record = {
        "status": "MIR-RECIPE-PRODUCTIVITY-PERMISSIONS-CONTROLS-PASSED",
        "assertions": int(result["assertions"]),
        "pipeline_sha256": hashlib.sha256(source.encode()).hexdigest(),
        "streams_sha256": hashlib.sha256(streams.encode()).hexdigest(),
        "published_baseline_assertions": published_baseline_assertions,
        "published_baselines": published_baselines,
        "descriptor_sha256": hashlib.sha256(descriptor.encode()).hexdigest(),
        "fixture_sha256": hashlib.sha256(fixture.encode()).hexdigest(),
        "semantics_sha256": hashlib.sha256(semantics_source.encode()).hexdigest(),
        "matcher_sha256": hashlib.sha256(matcher_source.encode()).hexdigest(),
        "planner_sha256": hashlib.sha256(planner_source.encode()).hexdigest(),
        "implicit_admission_absent_assertions": 1,
        "pipeline_assertions": int(pipeline_assertions),
        "runtime": "lupa.lua52",
        "factorio_processes": 0,
    }
    print(json.dumps(record, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
