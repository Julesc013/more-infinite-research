-- Exercises the shared continuation planner without starting Factorio.
local recipe_prototypes = {plate = {}, ["kr-imersite-powder"] = {}}
package.loaded["prototypes.mir.platform.factorio.data_raw"] = {
  prototype = function(kind, name)
    assert(kind == "recipe")
    return recipe_prototypes[name]
  end
}
local late_available = true
local unreachable_packs = {}
package.loaded["prototypes.mir.capabilities.science_integration.science_packs"] = {
  end_game_science_pack = function() return "promethium-science-pack" end,
  science_pack_exists = function() return late_available end,
  pack_production_status = function(name)
    return unreachable_packs[name] and "unreachable" or "research"
  end
}
local configured_maximum = "infinite"
package.loaded["prototypes.mir.planner.costs"] = {
  max_level_for = function() return configured_maximum end,
  base_cost_for = function() return 100 end
}
package.loaded["prototypes.mir.planner.prerequisites"] = {
  build_for = function() return {"automation"}, nil end
}
package.loaded["prototypes.mir.planner.science"] = {
  ingredients_for_selected = function(_, requested)
    return requested, "compatible", {policy = "fixture"}
  end
}
local scripted = true
local mod_data_supported = true
package.loaded["prototypes.mir.platform.factorio.target_line"] = {
  feature_enabled = function(name) return name == "scripted_techs" and scripted end,
  mod_data_supported = function() return mod_data_supported end
}
package.loaded["prototypes.mir.domain.research_cost.model"] = {
  evaluate = function() return 400 end,
  new = function(input) return {count_formula = "400+100*(L-4)", input = input} end
}
package.loaded["prototypes.mir.planner.stream_compiler.diagnostics"] = {
  plan_row = function(key, spec, action, reason, diagnostics, extra)
    local row = {stream_key = key, spec = spec, action = action, reason = reason,
      diagnostics = diagnostics}
    for field, value in pairs(extra or {}) do row[field] = value end
    return row
  end,
  skip_row = function(key, spec, reason)
    return {stream_key = key, spec = spec, action = "skip", reason = reason}
  end
}
package.loaded["prototypes.mir.report.diagnostics_sink"] = {
  stream_fields = function() return {status = "generated"} end
}

local progression = require("prototypes.mir.families.material_progression")
local continuation = require("prototypes.mir.planner.stream_compiler.material_continuation")
local spec = progression.attach("research_material_tin", {max_level = 3})
local legacy = {
  action = "emit",
  stream_key = "research_material_tin",
  technology_name = "recipe-prod-research_material_tin-1",
  spec = spec,
  fields = {
    effects = {{type = "change-recipe-productivity", recipe = "plate", change = 0.02}},
    ingredients = {{"automation-science-pack", 1}},
    cost_model = {base = 100}
  }
}
local assertions = 0
local function check(value, message)
  assert(value, message)
  assertions = assertions + 1
end

local stage = continuation.plan(legacy)
check(stage.action == "emit" and stage.stage_kind == "material-continuation",
  "qualified material receives a continuation")
check(stage.technology_name == "recipe-prod-research_material_tin-4"
    and stage.fields.level == 4 and stage.staged_parent_technology == legacy.technology_name,
  "the continuation preserves the legacy identity and begins at level four")
check(stage.planned_max_level == 150 and stage.fields.max_level == "infinite",
  "2.1 uses an effective finite cap over a lossless infinite prototype")
check(stage.fields.prerequisites[1] == "automation"
    and stage.fields.prerequisites[2] == legacy.technology_name,
  "late stage retains route prerequisites and requires the old technology")
check(stage.fields.ingredients[2][1] == "space-science-pack",
  "the first continuation uses attainable later science before final science")
check(stage.fields.cost_model.input.anchor_level == 4
    and stage.fields.cost_model.input.base_cost == 400
    and stage.fields.cost_model.input.linear_increment == 100,
  "later cost starts at the legacy next level without restarting at level one")
check(stage.fields.effects[1].recipe == legacy.fields.effects[1].recipe
    and stage.fields.effects[1].change == legacy.fields.effects[1].change,
  "the continuation retains the exact qualified effect")

-- A small positive effect and large upstream cap may imply more levels than
-- the engine can represent. An explicit finite cap still permits useful work.
recipe_prototypes.plate.maximum_productivity = 1000000
legacy.fields.effects[1].change = 0.0001
configured_maximum = 8
local bounded_stage = continuation.plan(legacy)
check(bounded_stage.action == "emit" and bounded_stage.planned_max_level == 8
    and bounded_stage.fields.level == 4 and bounded_stage.fields.max_level == "infinite",
  "the planner emits a bounded level-four stage despite oversized upstream headroom")
check(bounded_stage.technology_name == stage.technology_name
    and bounded_stage.fields.effects[1].change == 0.0001
    and bounded_stage.fields.effects[1].recipe == "plate",
  "bounding headroom preserves identity and the exact qualified effect")
mod_data_supported = false
check(continuation.plan(legacy).fields.max_level == 8,
  "the bounded continuation remains natively finite without mod-data transport")
mod_data_supported = true
configured_maximum = "infinite"
local oversized_stage = continuation.plan(legacy)
check(oversized_stage.action == "skip" and oversized_stage.reason == "material-level-domain-exceeded",
  "the planner withholds an unbounded oversized continuation")
configured_maximum = 3
local legacy_only_stage = continuation.plan(legacy)
check(legacy_only_stage.action == "skip"
    and legacy_only_stage.reason == "configured-material-cap-before-continuation",
  "the planner retains the explicit legacy-only setting disposition")
configured_maximum = "infinite"
legacy.fields.effects[1].change = 0.02
recipe_prototypes.plate.maximum_productivity = nil

local imersite_spec = progression.attach_k2_213_continuation("research_material_imersite", {max_level = 3})
local imersite_legacy = {
  action = "emit",
  stream_key = "research_material_imersite",
  technology_name = "recipe-prod-research_material_imersite-1",
  spec = imersite_spec,
  fields = {
    effects = {{type = "change-recipe-productivity", recipe = "kr-imersite-powder", change = 0.02}},
    ingredients = {{"automation-science-pack", 1}},
    cost_model = {base = 100}
  }
}
local imersite_stage = continuation.plan(imersite_legacy)
check(imersite_stage.action == "emit"
    and imersite_stage.technology_name == "recipe-prod-research_material_imersite-4"
    and imersite_stage.staged_parent_technology == imersite_legacy.technology_name,
  "the reviewed K2 powder route may continue only from its generated MIR legacy technology")
check(#imersite_stage.fields.effects == 1
    and imersite_stage.fields.effects[1].recipe == "kr-imersite-powder"
    and imersite_stage.fields.effects[1].change == 0.02,
  "the K2 continuation retains only the MIR-owned powder effect")
local imersite_native = {action = "adopt", spec = imersite_spec}
check(continuation.plan(imersite_native) == nil,
  "a K2 native-owner adoption cannot gain the Imersite continuation")

legacy.planned_max_level = 3
legacy.manifest_id = "research_material_tin"
local bindings = require("prototypes.mir.domain.technology.maximum_level_binding").from_plan(
  {stream_plan = {rows = {legacy, stage}}, fingerprint = "controlled-stage"},
  {scripted_techs_supported = true, mod_data_supported = true}
)
local by_name = {}
for _, binding in ipairs(bindings.bindings) do by_name[binding.technology_id] = binding end
check(by_name[legacy.technology_name].prototype_strategy.max_level == 3
    and by_name[legacy.technology_name].runtime_strategy.mode == "prototype-cap",
  "the released early stage must be natively finite before the level-four technology")
check(by_name[stage.technology_name].prototype_strategy.max_level == "infinite"
    and by_name[stage.technology_name].cap.effective == 150,
  "the later stage retains a lossless 2.1 prototype with a finite effective cap")

mod_data_supported = false
local f200_stage = continuation.plan(legacy)
check(f200_stage.fields.max_level == 150,
  "2.0 uses a native finite later stage without a mod-data policy transport")
local f200_bindings = require("prototypes.mir.domain.technology.maximum_level_binding").from_plan(
  {stream_plan = {rows = {legacy, f200_stage}}, fingerprint = "controlled-f200-stage"},
  {scripted_techs_supported = true, mod_data_supported = false}
)
local f200_by_name = {}
for _, binding in ipairs(f200_bindings.bindings) do
  f200_by_name[binding.technology_id] = binding
end
check(f200_by_name[f200_stage.technology_name].prototype_strategy.max_level == 150
    and f200_by_name[f200_stage.technology_name].runtime_strategy.mode == "prototype-cap",
  "2.0 binds the later stage to the native finite prototype maximum")
unreachable_packs["space-science-pack"] = true
unreachable_packs["utility-science-pack"] = true
unreachable_packs["promethium-science-pack"] = true
local established_frontier = {
  action = legacy.action,
  stream_key = legacy.stream_key,
  technology_name = legacy.technology_name,
  spec = legacy.spec,
  fields = {}
}
for key, value in pairs(legacy.fields) do established_frontier.fields[key] = value end
established_frontier.fields.ingredients = {
  {"automation-science-pack", 1}, {"production-science-pack", 1}
}
local same_frontier_stage = continuation.plan(established_frontier)
check(same_frontier_stage.action == "emit"
    and #same_frontier_stage.fields.ingredients == 2
    and same_frontier_stage.fields.ingredients[2][1] == "production-science-pack",
  "an established highest reachable science tier may carry useful later levels")
unreachable_packs = {}
mod_data_supported = true
scripted = false
check(continuation.plan(legacy).fields.max_level == 150,
  "older targets materialize a native finite cap")
scripted = true
late_available = false
local missing = continuation.plan(legacy)
check(missing.action == "skip" and missing.reason == "no_reachable_late_science_frontier",
  "an unavailable later science route withholds the stage")
late_available = true
local adopted = {action = "adopt", spec = spec}
check(continuation.plan(adopted) == nil,
  "a native owner cannot be extended as an MIR generated family")

-- The late mutation policy must agree with the compiler and binding. The
-- native engine rejects a level-four technology after an infinite `-1` row.
package.loaded["prototypes.mir.streams.registry"] = {
  snapshot = function() return {research_material_tin = spec} end
}
package.loaded["prototypes.mir.platform.factorio.data_raw"].technology =
  function(name) return name == legacy.technology_name and {} or nil end
local max_policy = require("prototypes.mir.policy.max_level")
check(max_policy.plan()[1].max_level == 3
    and max_policy.plan()[1].planned_max_level == 3,
  "the late mutation policy keeps the early prototype natively finite")
scripted = false
check(max_policy.plan()[1].max_level == 3,
  "the older-target late mutation policy agrees with the early stage")
print("MIR-MATERIAL-CONTINUATION-PASS " .. assertions)
