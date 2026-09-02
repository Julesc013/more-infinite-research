local D = require("prototypes.mir.report.diagnostics_sink")
local native_owner_binding = require("prototypes.mir.planner.native_owner_binding")
local costs = require("prototypes.mir.planner.costs")
local icon_builder = require("prototypes.mir.presentation.icon_builder")
local owner_policy = require("prototypes.mir.policy.owner_policy")
local recipe_productivity_planner = require("prototypes.mir.capabilities.recipe_productivity.planner")
local direct_effects_planner = require("prototypes.mir.planner.direct_effects")
local native_effect_coverage = require("prototypes.mir.policy.native_effect_coverage")
local planner_requirements = require("prototypes.mir.planner.requirements")
local planner_prerequisites = require("prototypes.mir.planner.prerequisites")
local planner_science = require("prototypes.mir.planner.science")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local effect_scaling = require("prototypes.mir.settings.effect_scaling")
local automatic_compiler_policy = require("prototypes.mir.settings.automatic_compiler_policy")
local compatibility_policy = require("prototypes.mir.compatibility.policy_authority")
local research_cost_classification = require("prototypes.mir.domain.research_cost.classification")
local discover = require("prototypes.mir.planner.stream_compiler.discover")
local ownership = require("prototypes.mir.planner.stream_compiler.ownership")
local diagnostics = require("prototypes.mir.planner.stream_compiler.diagnostics")

local M = {}

local lname = diagnostics.localized_name
local ldesc = diagnostics.localized_description
local expand_dynamic_items = discover.expand_dynamic_items

local plan_row = diagnostics.plan_row
local skip_row = diagnostics.skip_row
local attach_family_recipes = ownership.attach_family_recipes

local function plan_stream(key, raw_spec)
  if raw_spec.automatic_family then
    local authorization = compatibility_policy.authorizes_family_stream(key)
    local maturity = type(raw_spec.automatic_family) == "table"
      and raw_spec.automatic_family.creation_maturity
      or "reviewed"
    local allowed, reason = automatic_compiler_policy.generation_decision(authorization, maturity)
    if not allowed then
      return skip_row(key, raw_spec, reason, nil, nil, nil, nil, {
        target_supported = {evidence = "automatic-compiler-policy:" .. reason, reason = reason}
      })
    end
  end
  if not costs.enabled_for(key, raw_spec) then
    return skip_row(key, raw_spec, "disabled")
  end
  local missing = planner_requirements.missing_reason(key, raw_spec)
  if missing then
    return skip_row(key, raw_spec, missing, nil, nil, nil, nil, {
      target_supported = {evidence = "requirements:" .. missing, reason = missing}
    })
  end

  local spec = expand_dynamic_items(raw_spec)

  local technology_name = spec.technology_name or ("recipe-prod-" .. key .. "-1")
  local first_level = research_cost_classification.anchor_level(technology_name, 1)
  local cost_model = costs.model_for(key, spec, first_level)
  local max_level = costs.max_level_for(key, spec)
  local prototype_max_level = target_line.feature_enabled("scripted_techs")
    and "infinite" or max_level
  local count_formula = cost_model.count_formula
  local research_time = costs.research_time_for(key, spec)

  local direct_effects = nil
  if spec.direct_effects then
    direct_effects = direct_effects_planner.available_for_stream(key, spec)
    if #direct_effects == 0 then
      return skip_row(key, spec, "no_available_direct_effects", nil, direct_effects, nil, nil, {
        effect_valid = {evidence = "direct-effect-planner:empty", reason = "no_available_direct_effects"}
      })
    end
    if spec.adopt_exact_native_effect_owner and not native_effect_coverage.prefer_mir() then
      local covered, owners = native_effect_coverage.external_coverage_for_effects(direct_effects)
      if covered then
        return skip_row(key, spec, "covered_by_existing_infinite_native_modifier", nil, direct_effects, nil, {
          owners = table.concat(owners, ",")
        }, {
          owner_conflict_free = {evidence = "owner-index:existing-native-owner", reason = "covered_by_existing_infinite_native_modifier"}
        })
      end
    end
  end

  local ingredients, lab_status = planner_science.ingredients_for_stream(key, spec)
  if not ingredients or #ingredients == 0 then
    return skip_row(key, spec, "no_lab_compatible_science", ingredients, direct_effects, lab_status, nil, {
      science_compatible = {evidence = "science-selector:no-compatible-set", reason = "no_lab_compatible_science"},
      lab_compatible = {evidence = "lab-matrix:no-accepting-lab", reason = "no_lab_compatible_science"}
    })
  end

  if direct_effects and #direct_effects > 0 then
    local prerequisites, prerequisite_reason = planner_prerequisites.build_for(key, ingredients)
    if prerequisite_reason then
      return skip_row(key, spec, prerequisite_reason, ingredients, direct_effects, lab_status, nil, {
        progression_safe = {evidence = "prerequisite-planner:" .. prerequisite_reason, reason = prerequisite_reason}
      })
    end
    local emitted_effects = effect_scaling.scale_stream_effects(key, spec, direct_effects)
    local fields = {
      localised_name = lname(key, spec),
      localised_description = ldesc(spec),
      icons = icon_builder.icons_for_stream(spec),
      effects = emitted_effects,
      prerequisites = prerequisites,
      count_formula = count_formula,
      cost_model = cost_model,
      ingredients = ingredients,
      research_time = research_time,
      max_level = prototype_max_level,
    }
    return plan_row(key, spec, "emit", "direct_effect",
      D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, emitted_effects, lab_status), {
        technology_name = technology_name,
        fields = fields,
        planned_max_level = max_level,
        direct_effects = true,
        overlap_effects = direct_effects
      })
  end

  if not target_line.feature_enabled("recipe_productivity") then
    return skip_row(key, spec, "recipe_productivity_unsupported", ingredients, {}, lab_status, nil, {
      target_supported = {evidence = "target-profile:recipe-productivity-disabled", reason = "recipe_productivity_unsupported"}
    })
  end

  local buckets = recipe_productivity_planner.match_buckets(key, spec)
  buckets = attach_family_recipes(key, buckets)
  local covered_by_existing
  buckets, covered_by_existing = owner_policy.filter_existing_recipe_productivity(key, spec, buckets)
  local adopted_effects, family_blocked, adoption_owner_name, adoption
  buckets, adopted_effects, family_blocked, adoption_owner_name, adoption = native_owner_binding.plan(key, spec, buckets)
  if adoption then
    return plan_row(key, spec, "adopt", adoption.operation,
      D.stream_fields(key, spec, "adopted", adoption.operation, ingredients, nil, adopted_effects, lab_status, {
        owners = adoption_owner_name,
        recipes = owner_policy.recipe_names_from_effects(adopted_effects)
      }), {
        adoption = adoption
      })
  end
  local effects = recipe_productivity_planner.effects_from_buckets(key, buckets)
  if #effects == 0 then
    if adoption then
      error("GenerationPlan adoption row was not created for stream " .. key)
    end
    local reason = "no_matching_recipes"
    if covered_by_existing and #covered_by_existing > 0 then
      reason = "covered_by_existing_infinite_recipe_productivity"
    elseif family_blocked and #family_blocked > 0 then
      reason = family_blocked[1].reason
    end
    local failed_gates = {
      effect_valid = {evidence = "recipe-matcher:no-materializable-effects", reason = reason}
    }
    if covered_by_existing and #covered_by_existing > 0 then
      failed_gates = {
        owner_conflict_free = {evidence = "owner-index:blocking-owner", reason = reason}
      }
    end
    return skip_row(key, spec, reason, ingredients, effects, lab_status, nil, failed_gates)
  end

  local prerequisites, prerequisite_reason = planner_prerequisites.build_for(key, ingredients)
  if prerequisite_reason then
    return skip_row(key, spec, prerequisite_reason, ingredients, effects, lab_status, nil, {
      progression_safe = {evidence = "prerequisite-planner:" .. prerequisite_reason, reason = prerequisite_reason}
    })
  end
  local emitted_effects = effect_scaling.scale_stream_effects(key, spec, effects)
  local fields = {
    localised_name = lname(key, spec),
    localised_description = ldesc(spec),
    icons = icon_builder.icons_for_stream(spec),
    effects = emitted_effects,
    prerequisites = prerequisites,
    count_formula = count_formula,
    cost_model = cost_model,
    ingredients = ingredients,
    research_time = research_time,
    max_level = prototype_max_level,
  }
  return plan_row(key, spec, "emit", "recipe_productivity",
    D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, emitted_effects, lab_status), {
      technology_name = technology_name,
      fields = fields,
      planned_max_level = max_level,
      direct_effects = false
    })
end

function M.plan(key, raw_spec)
  return plan_stream(key, raw_spec)
end

return M
