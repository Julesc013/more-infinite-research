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
local end_game_pack = "promethium-science-pack"
local science_technologies, science_unlockers, science_states = {}, {}, {}
local prerequisite_queries = 0
local science_services = {
  ["science.prereq_techs_for_science_pack"] = function(pack)
    prerequisite_queries = prerequisite_queries + 1
    return science_unlockers[pack] or {}
  end
}
package.loaded["prototypes.mir.pipeline.compiler_context"] = {
  current = function() return {
    service = function(_, name) return science_services[name] end,
    state_view = function(_, name, build)
      if not science_states[name] then science_states[name] = build() end
      return science_states[name]
    end
  } end
}
package.loaded["prototypes.mir.platform.factorio.data_raw"].technology = function(name) return science_technologies[name] end
package.loaded["prototypes.mir.platform.factorio.prototype_lookup"] = {}
package.loaded["prototypes.mir.capabilities.science_integration.lab_compatibility"] = {
  ingredient_name = function(ingredient) return ingredient.name or ingredient[1] end
}
package.loaded["prototypes.mir.capabilities.science_integration.pack_registry"] = {
  science_pack_exists = function() return late_available end,
  ordered_pack_list_from_set = function(set)
    local packs = {}; for pack in pairs(set) do packs[#packs + 1] = pack end
    table.sort(packs); return packs
  end
}
local science_policy = require("prototypes.mir.capabilities.science_integration.science_selection_policy")
package.loaded["prototypes.mir.capabilities.science_integration.science_packs"] = {
  end_game_science_pack = function() return end_game_pack end,
  mod_progression_packs_for = science_policy.mod_progression_packs_for,
  official_progression_packs_for = science_policy.official_progression_packs_for,
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
local incompatible_frontier
package.loaded["prototypes.mir.planner.science"] = {
  ingredients_for_selected = function(_, requested)
    for _, ingredient in ipairs(requested) do
      if ingredient[1] == incompatible_frontier then return nil, "invalid" end
    end
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

-- An already required later pack must not turn a lower ordinary pack into
-- a new frontier. These cases exercise the real shared planner, retaining
-- the established space-first preference for an earlier material stage.
local original_ingredients = legacy.fields.ingredients
legacy.fields.ingredients = {{"automation-science-pack", 2}, {"space-science-pack", 3}}
local advanced_frontier = continuation.plan(legacy)
check(#advanced_frontier.fields.ingredients == 2
    and advanced_frontier.fields.ingredients[2][1] == "space-science-pack",
  "an existing space frontier keeps its established tier before final science instead of adding utility")
check(advanced_frontier.fields.ingredients[1][2] == 2
    and advanced_frontier.fields.ingredients[2][2] == 3
    and advanced_frontier.fields.effects[1].recipe == "plate",
  "frontier advancement preserves inherited amounts and admitted effects")
unreachable_packs["promethium-science-pack"] = true
local carried_frontier = continuation.plan(legacy)
check(#carried_frontier.fields.ingredients == 2
    and carried_frontier.fields.ingredients[2][1] == "space-science-pack",
  "an unavailable higher frontier carries the established tier without adding lower utility")
unreachable_packs = {}
legacy.fields.ingredients = original_ingredients
incompatible_frontier = "space-science-pack"
local lab_carried = continuation.plan(legacy)
check(#lab_carried.fields.ingredients == 2
    and lab_carried.fields.ingredients[2][1] == "utility-science-pack",
  "an unusable joint lab set tries the next qualified ordinary frontier")
incompatible_frontier = nil
legacy.fields.ingredients = {{"automation-science-pack", 2}, {"promethium-science-pack", 5}}
local final_frontier = continuation.plan(legacy)
check(#final_frontier.fields.ingredients == 2
    and final_frontier.fields.ingredients[2][1] == "promethium-science-pack"
    and final_frontier.fields.ingredients[2][2] == 5,
  "an existing highest end-game tier cannot add a lower space frontier")
legacy.fields.ingredients = original_ingredients

-- Planet branches and an unfamiliar mod-science name use the actual shared
-- progression policy, rather than a fixture colour/rank table.
for _, pack in ipairs({"agricultural-science-pack", "metallurgic-science-pack",
    "electromagnetic-science-pack", "cryogenic-science-pack"}) do
  legacy.fields.ingredients = {{pack, 4}}
  local carried_planet = continuation.plan(legacy)
  check(#carried_planet.fields.ingredients == 1 and carried_planet.fields.ingredients[1][1] == pack,
    "a planetary frontier cannot descend to ordinary space science: " .. pack)
end
science_technologies.CardGate = {unit = {ingredients = {{"space-science-pack", 1}}}}
science_unlockers["unfamiliar-late-card"] = {"CardGate"}
legacy.fields.ingredients = {{"unfamiliar-late-card", 7}}
local mod_frontier = continuation.plan(legacy)
check(#mod_frontier.fields.ingredients == 1
    and mod_frontier.fields.ingredients[1][2] == 7
    and mod_frontier.fields.ingredients[1][1] == "unfamiliar-late-card",
  "an unfamiliar card's concrete prerequisite prevents a downward space frontier")
unreachable_packs["promethium-science-pack"] = true
local mod_carried = continuation.plan(legacy)
check(#mod_carried.fields.ingredients == 1
    and mod_carried.fields.ingredients[1][1] == "unfamiliar-late-card"
    and mod_carried.fields.ingredients[1][2] == 7,
  "an established mod-science frontier can carry useful levels without lower additions")
local prior_queries = prerequisite_queries
continuation.plan(legacy)
check(prerequisite_queries == prior_queries,
  "repeated material frontier queries reuse the existing context-scoped prerequisite cache")
legacy.fields.ingredients = {{"cryogenic-science-pack", 4}}
check(#continuation.plan(legacy).fields.ingredients == 1,
  "an established planetary frontier carries its required pack when end-game science is unavailable")
unreachable_packs = {}
end_game_pack = "space-science-pack"
legacy.fields.ingredients = {{"space-science-pack", 3}}
check(#continuation.plan(legacy).fields.ingredients == 1,
  "the base end-game alias does not promote utility above space")
end_game_pack = "promethium-science-pack"
legacy.fields.ingredients = original_ingredients
unreachable_packs = {['space-science-pack'] = true, ['utility-science-pack'] = true,
  ['production-science-pack'] = true}
check(continuation.plan(legacy).fields.ingredients[2][1] == "promethium-science-pack",
  "a profile with no ordinary or inherited late frontier retains the final-pack escape")
incompatible_frontier = "promethium-science-pack"
check(continuation.plan(legacy).reason == "no_reachable_late_science_frontier",
  "the final-pack escape cannot bypass an unusable joint lab set")
incompatible_frontier = nil
unreachable_packs = {}

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

-- These subjects are the retained requested outcomes, independent of the
-- production key accessor. An emitted early row represents an already
-- admitted route; this fixture does not certify any overhaul recipe graph.
for _, subject in ipairs({
  {"research_material_rare_metals", "kr-rare-metals"},
  {"research_material_silicon", "kr-silicon"},
  {"research_material_glass", "kr-glass"},
  {"research_material_black_paving", "kr-black-reinforced-plate"},
  {"research_material_white_paving", "kr-white-reinforced-plate"},
  {"research_material_nitric_acid", "angels-liquid-nitric-acid", "angel"},
  {"research_material_hydrochloric_acid", "angels-liquid-hydrochloric-acid", "angel"},
  {"research_material_hydrofluoric_acid", "angels-liquid-hydrofluoric-acid", "angel"},
  {"research_material_glycerol", "angels-liquid-glycerol", "angel"}
}) do
  local key, recipe_name = subject[1], subject[2]
  recipe_prototypes[recipe_name] = {maximum_productivity = 3}
  local attach = subject[3] == "angel" and progression.attach_angel_petrochem_continuation
    or progression.attach_k2_material_continuation
  local family = attach(key, {max_level = 3})
  local early = {
    action = "emit", stream_key = key, technology_name = "recipe-prod-" .. key .. "-1", spec = family,
    planned_max_level = 3,
    fields = {effects = {{type = "change-recipe-productivity", recipe = recipe_name, change = 0.02}},
      ingredients = {{"automation-science-pack", 1}}, cost_model = {base = 100}}
  }
  mod_data_supported = true
  configured_maximum = "infinite"
  local later = continuation.plan(early)
  check(later.action == "emit" and later.technology_name == "recipe-prod-" .. key .. "-4"
      and later.fields.level == 4 and later.planned_max_level == 150 and later.fields.max_level == "infinite",
    "F210 plans the separate useful continuation for " .. key)
  check(later.fields.effects[1].recipe == recipe_name and later.fields.effects[1].change == 0.02
      and later.fields.prerequisites[2] == early.technology_name
      and later.fields.cost_model.input.anchor_level == 4,
    "continuation preserves the admitted recipe, increment, predecessor and cost anchor for " .. key)
  local f210_bindings = require("prototypes.mir.domain.technology.maximum_level_binding").from_plan(
    {stream_plan = {rows = {early, later}}, fingerprint = "controlled-" .. key},
    {scripted_techs_supported = true, mod_data_supported = true})
  local f210_by_name = {}
  for _, binding in ipairs(f210_bindings.bindings) do f210_by_name[binding.technology_id] = binding end
  check(f210_by_name[early.technology_name].prototype_strategy.max_level == 3
      and f210_by_name[later.technology_name].prototype_strategy.max_level == "infinite"
      and f210_by_name[later.technology_name].cap.effective == 150,
    "F210 binds the finite early stage and later effective cap for " .. key)
  mod_data_supported = false
  local native_later = continuation.plan(early)
  check(native_later.fields.max_level == 150 and native_later.planned_max_level == 150,
    "F200 retains a finite native useful cap for " .. key)
  local f200_bindings = require("prototypes.mir.domain.technology.maximum_level_binding").from_plan(
    {stream_plan = {rows = {early, native_later}}, fingerprint = "controlled-f200-" .. key},
    {scripted_techs_supported = true, mod_data_supported = false})
  local f200_by_name = {}
  for _, binding in ipairs(f200_bindings.bindings) do f200_by_name[binding.technology_id] = binding end
  check(f200_by_name[native_later.technology_name].prototype_strategy.max_level == 150
      and f200_by_name[native_later.technology_name].runtime_strategy.mode == "prototype-cap",
    "F200 binds the later native prototype without mod-data transport for " .. key)
  configured_maximum = 3
  local stopped = continuation.plan(early)
  check(stopped.action == "skip" and stopped.reason == "configured-material-cap-before-continuation",
    "an explicit old cap three still prevents the later stage for " .. key)
  configured_maximum = 4
  check(continuation.plan(early).fields.max_level == 4,
    "an explicit cap four is absolute across both stages for " .. key)
  configured_maximum = "infinite"
  recipe_prototypes[recipe_name].maximum_productivity = 0.06
  check(continuation.plan(early).reason == "no-continuation-headroom",
    "early saturation cannot create paid no-op research for " .. key)
  recipe_prototypes[recipe_name].maximum_productivity = 3
  late_available = false
  check(continuation.plan(early).reason == "no_reachable_late_science_frontier",
    "missing reachable science withholds the later stage for " .. key)
  late_available = true
  for _, action in ipairs({"skip", "adopt"}) do
    early.action = action
    check(continuation.plan(early) == nil,
      "continuation cannot revive a withheld route or replace a native owner for " .. key)
  end
end
mod_data_supported = true

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
