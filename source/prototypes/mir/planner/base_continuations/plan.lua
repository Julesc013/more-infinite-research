local defaults = require("prototypes.mir.settings.defaults")

local base_defaults = defaults.base_extensions or {}

local classify = require("prototypes.mir.planner.base_continuations.classify")
local discover = require("prototypes.mir.planner.base_continuations.discover")
local qualify = require("prototypes.mir.planner.base_continuations.qualify")
local D = require("prototypes.mir.report.diagnostics_sink")
local deepcopy = require("prototypes.mir.core.deepcopy")
local table_utils = require("prototypes.mir.core.table")
local effect_safety = require("prototypes.mir.domain.technology.effect_safety_policy")
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local effect_scaling = require("prototypes.mir.settings.effect_scaling")
local base_extension_builder = require("prototypes.mir.planner.base_continuation_builder")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_risk = require("prototypes.mir.domain.technology.technology_risk")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")
local cost_contract = require("prototypes.mir.settings.cost_contract")
local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

local function format_number(value)
  if type(value) ~= "number" then return tostring(value) end
  if math.abs(value - math.floor(value)) < 1e-6 then
    return tostring(math.floor(value + 0.5))
  end
  return string.format("%.6g", value)
end

local function legacy_formula_number(value)
  local numeric = tonumber(format_number(value))
  if not numeric then error("Unable to preserve legacy base-continuation formula number.", 2) end
  return numeric
end

local function build_inserter_effects(last, spec)
  spec = spec or {}
  local bulk_increment = spec.bulk_increment or spec.stack_increment or 4
  local non_bulk_increment = spec.non_bulk_increment or spec.non_stack_increment or 2
  local out = {}
  for _, effect in ipairs(last.effects or {}) do
    local copy = deepcopy(effect)
    if copy.type == "bulk-inserter-capacity-bonus" or copy.type == "stack-inserter-capacity-bonus" then
      copy.modifier = bulk_increment
    elseif copy.type == "inserter-stack-size-bonus" then
      copy.modifier = non_bulk_increment
    end
    table.insert(out, copy)
  end
  return out
end

local SPECIALS = {
  ["inserter-capacity-bonus"] = {
    effect_builder = build_inserter_effects
  }
}

local function plan_chain(key)
  local spec = base_defaults[key] or {}
  local chain_key = spec.chain_key or key
  local generated_key = spec.generated_key or chain_key
  local locale_key = spec.locale_key or chain_key
  if not qualify.is_enabled(key, spec) then
    D.extension(D.extension_fields(key, "skipped", "disabled"))
    return classify.rejected_candidate(key, "disabled")
  end

  local levels, by_level, has_infinite = discover.chain(chain_key)

  if has_infinite or #levels == 0 then
    D.extension(D.extension_fields(key, "skipped", has_infinite and "already_infinite" or "no_vanilla_chain"))
    return classify.rejected_candidate(key, has_infinite and "already_infinite" or "no_vanilla_chain", "target_supported")
  end

  local detected_highest = levels[#levels]
  local min_level = spec.min_level or (detected_highest + 1)
  if detected_highest < min_level - 1 then
    -- Vanilla chain does not reach the expected prerequisite tier.
    D.extension(D.extension_fields(key, "skipped", "vanilla_chain_below_minimum"))
    return classify.rejected_candidate(key, "vanilla_chain_below_minimum", "target_supported")
  end

  local extend_from_level = math.max(detected_highest, min_level - 1)
  if extend_from_level < min_level - 1 then extend_from_level = min_level - 1 end
  local base_level = extend_from_level
  local desired_new_level = extend_from_level + 1

  if desired_new_level < min_level then
    -- Need to catch up to the minimum level; treat the next vanilla level as base.
    base_level = min_level - 1
    desired_new_level = min_level
  end

  local base_tech = by_level[base_level]
  if not base_tech or not base_tech.unit then
    D.extension(D.extension_fields(key, "skipped", "missing_base_unit"))
    return classify.rejected_candidate(key, "missing_base_unit", "progression_safe")
  end
  if base_tech.max_level == "infinite" then
    D.extension(D.extension_fields(key, "skipped", "base_already_infinite"))
    return classify.rejected_candidate(key, "base_already_infinite", "output_identity_safe")
  end
  local base_researchability_reason = science_packs.technology_researchability_reason(chain_key .. "-" .. base_level)
  if base_researchability_reason then
    D.extension(D.extension_fields(key, "skipped", "unresearchable_base_technology_" .. base_researchability_reason))
    return classify.rejected_candidate(key, "unresearchable_base_technology_" .. base_researchability_reason, "science_compatible")
  end
  -- Allow anchoring when the base tech exists; vanilla-derived cost inference
  -- still requires numeric unit.count values.

  local new_name = generated_key .. "-" .. desired_new_level
  -- Never replace an existing vanilla or modded continuation level.
  if discover.technology(new_name) then
    D.extension(D.extension_fields(key, "skipped", "target_exists"))
    return classify.rejected_candidate(key, "target_exists", "output_identity_safe")
  end

  local max_level_value = qualify.coerce_max_level_value(qualify.startup_setting("mir-max-level-" .. key))
  if max_level_value == "infinite" then
    max_level_value = qualify.coerce_max_level_value(spec.max_level)
  end
  local retain_for_runtime_cap = target_line.feature_enabled("scripted_techs")
    and max_level_value ~= "infinite"
    and max_level_value < desired_new_level
  if max_level_value ~= "infinite" and max_level_value < desired_new_level
      and not retain_for_runtime_cap then
    D.extension(D.extension_fields(key, "skipped", "max_level_below_first_extension"))
    return classify.rejected_candidate(key, "max_level_below_first_extension", "progression_safe")
  end
  if retain_for_runtime_cap then
    log("[more-infinite-research] Retaining disabled base continuation for lossless cap migration: "
      .. new_name .. " selected=" .. tostring(max_level_value)
      .. " first-level=" .. tostring(desired_new_level) .. ".")
  end

  local last_count = base_tech.unit.count
  local prev_unit = discover.previous_unit(base_level, by_level)

  local growth_setting = qualify.sanitize_number(qualify.startup_setting("mir-cost-growth-" .. key))
  local force_vanilla_growth = growth_setting == 0
  local growth = nil
  local growth_provenance = nil
  if growth_setting and growth_setting > 0 then
    growth = growth_setting
    growth_provenance = cost_contract.base_name("growth_factor", key)
  end
  if not growth and not force_vanilla_growth then
    local default_growth = qualify.sanitize_number(spec.growth_factor)
    if default_growth and default_growth > 0 then
      growth = default_growth
      growth_provenance = "base-extension-default:" .. key
    end
  end
  if not growth then
    growth = discover.compute_growth_from_prev(base_tech.unit, prev_unit)
    if growth then growth_provenance = "vanilla-chain-inheritance" end
  end
  if not growth then
    growth = discover.compute_growth_fallback(levels, by_level, base_level, last_count, prev_unit)
    if growth then growth_provenance = "vanilla-chain-fallback" end
  end
  if not growth or growth < 1 then
    growth = 1
    growth_provenance = "nondecreasing-safety-floor"
  end

  local base_setting = qualify.sanitize_number(qualify.startup_setting("mir-cost-base-" .. key))
  local force_vanilla_base = base_setting == 0
  -- The stable mir-cost-base-* setting predates ResearchCostModel and is a
  -- global L=1 coefficient. Preserve that ABI, then project it to the first
  -- controlled continuation level used by the canonical anchored model.
  local base_coefficient = nil
  local base_provenance = nil
  if base_setting and base_setting > 0 then
    base_coefficient = base_setting
    base_provenance = cost_contract.base_name("base_cost", key)
  end

  if not base_coefficient and not force_vanilla_base then
    local spec_base = qualify.sanitize_number(spec.base_cost)
    if spec_base and spec_base > 0 then
      base_coefficient = spec_base
      base_provenance = "base-extension-default:" .. key
    end
  end
  if not base_coefficient then
    if last_count and growth > 0 then
      base_coefficient = last_count / (growth ^ (base_level - 1))
      base_provenance = "vanilla-chain-inheritance"
    end
  end
  if not base_coefficient or base_coefficient <= 0 then
    base_coefficient = 1000
    base_provenance = "vanilla-chain-fallback"
  end

  local linear_increment = qualify.sanitize_number(qualify.startup_setting(cost_contract.base_name("linear_increment", key)))
  local increment_provenance = cost_contract.base_name("linear_increment", key)
  if not linear_increment or linear_increment < 0 then
    linear_increment = qualify.sanitize_number(spec.linear_increment) or 0
    increment_provenance = "base-extension-default:" .. key
  end
  -- The pre-3.2.5 formula emitter canonicalized both operands to six
  -- significant digits. Retain that realized curve before changing its
  -- representation from an L=1 formula to an anchored model.
  base_coefficient = legacy_formula_number(base_coefficient)
  growth = legacy_formula_number(growth)
  local first_level_base = base_coefficient * (growth ^ (desired_new_level - 1))
  local cost_model = research_cost_model.new({
    anchor_level = desired_new_level,
    base_cost = first_level_base,
    linear_increment = linear_increment,
    growth_factor = growth,
    provenance = {
      base_cost = "legacy-six-digit-coefficient-projection:" .. base_provenance,
      linear_increment = increment_provenance,
      growth_factor = "legacy-six-digit-growth-projection:" .. growth_provenance,
      anchor_level = "technology-first-level"
    }
  })

  local new = base_extension_builder.continuation(base_tech, {
    name = new_name,
    localised_name = spec.localised_name or base_tech.localised_name or {"technology-name." .. locale_key},
    localised_description = technology_risk.append_tooltip(
      spec.localised_description or base_tech.localised_description or {"technology-description." .. locale_key},
      spec.technology_risk),
    prerequisites = qualify.build_prerequisites(chain_key .. "-" .. base_level, base_tech.prerequisites),
    effects = {},
    unit = {},
    max_level = "infinite",
    upgrade = true,
    level = desired_new_level,
    hidden = retain_for_runtime_cap
  })

  local special = SPECIALS[key]
  local desired_effects = nil
  if special and special.effect_builder then
    desired_effects = special.effect_builder(base_tech, spec)
  else
    desired_effects = deepcopy(base_tech.effects or {})
  end
  effect_safety.assert_effects_allowed(desired_effects, "base extension " .. key)
  if not qualify.prefer_this_mod_for_competing_techs() then
    local other_choice = discover.find_any_infinite_extension(chain_key .. "-" .. base_level, new_name)
    if other_choice then
      log("[more-infinite-research] Skipping extension for " .. key .. ": competing infinite tech kept from other mod (" .. other_choice .. ").")
      D.extension(D.extension_fields(key, "skipped", "competing_infinite_kept"))
      return classify.rejected_candidate(key, "competing_infinite_kept", "owner_conflict_free")
    end
  end
  local existing = discover.find_equivalent_infinite_extension(chain_key .. "-" .. base_level, desired_effects)
  if existing then
    log("[more-infinite-research] Skipping extension for " .. key .. ": equivalent infinite tech already exists (" .. existing .. ").")
    D.extension(D.extension_fields(key, "skipped", "equivalent_infinite_exists"))
    return classify.rejected_candidate(key, "equivalent_infinite_exists", "owner_conflict_free")
  end
  new.effects = effect_scaling.scale_base_effects(key, desired_effects)

  new.max_level = target_line.feature_enabled("scripted_techs")
    and "infinite"
    or max_level_value
  new.upgrade = true

  local research_setting = qualify.sanitize_number(qualify.startup_setting("mir-research-time-" .. key))
  local force_vanilla_time = research_setting == 0
  local research_time = nil
  if research_setting and research_setting > 0 then
    research_time = research_setting
  end
  if not research_time and not force_vanilla_time then
    research_time = qualify.sanitize_number(spec.research_time)
  end
  if not research_time or research_time <= 0 then
    research_time = base_tech.unit.time or 60
  end

  local resolved_ingredients, lab_status, science_phase_decision = qualify.resolve_ingredients(spec, base_tech.unit, key)
  if not resolved_ingredients or #resolved_ingredients == 0 then
    log("[more-infinite-research] Skipping extension for " .. key .. ": no lab-compatible science pack set was found.")
    D.extension(D.extension_fields(key, "skipped", "no_lab_compatible_science", resolved_ingredients, new.prerequisites, desired_effects, lab_status))
    return classify.rejected_candidate(key, "no_lab_compatible_science", "lab_compatible")
  end
  new.unit = {
    count_formula = cost_model.count_formula,
    ingredients = resolved_ingredients,
    time = research_time
  }
  local prerequisite_reason
  new.prerequisites, prerequisite_reason = qualify.append_end_game_prerequisite(new.prerequisites, resolved_ingredients)
  if prerequisite_reason then
    log("[more-infinite-research] Skipping extension for " .. key .. ": " .. prerequisite_reason .. ".")
    D.extension(D.extension_fields(key, "skipped", prerequisite_reason, resolved_ingredients, new.prerequisites, desired_effects, lab_status))
    return classify.rejected_candidate(key, prerequisite_reason, "prerequisites_acyclic")
  end

  if special and special.on_extend then
    special.on_extend(new, base_tech, spec)
  end

  local operation = {
    schema = 1,
    operation = "emit_base_extension",
    key = key,
    manifest_id = spec.manifest_id or ("base-continuation/" .. key),
    base_technology_name = chain_key .. "-" .. base_level,
    technology_name = new.name,
    technology = new,
    planned_max_level = max_level_value,
    research_cost_model = cost_model,
    science_phase_policy = science_phase_decision,
    technology_risk = technology_risk.classification(spec.technology_risk),
    diagnostics = D.extension_fields(
      key,
      "generated",
      retain_for_runtime_cap and "migration_retention_below_configured_cap" or "base_extension",
      resolved_ingredients,
      new.prerequisites,
      new.effects,
      lab_status),
    gates = classify.accepted_gate_vector(key, new.name)
  }
  operation.technology_design = technology_design.from_base_extension_operation(operation)
  operation.technology = technology_design.prototype_projection(operation.technology_design, {validated = true})
  operation.technology.type = "technology"
  return operation
end

function M.plan_all()
  local plan, candidates, names = {}, {}, {}
  for _, key in ipairs(table_utils.sorted_keys(base_defaults)) do
    local operation, rejected = plan_chain(key)
    if operation then
      if names[operation.technology_name] then
        error("Base extension plan contains duplicate technology name: " .. operation.technology_name, 2)
      end
      names[operation.technology_name] = true
      table.insert(plan, operation)
      table.insert(candidates, {
        schema = 1,
        candidate_id = "base-continuation/" .. tostring(key),
        key = key,
        action = "create",
        technology_name = operation.technology_name,
        technology_risk = deepcopy(operation.technology_risk),
        design_fingerprint = operation.technology_design.design_fingerprint,
        gates = deepcopy(operation.gates),
        candidate_fingerprint = fingerprint.of({key = key, technology_name = operation.technology_name,
          technology_risk = operation.technology_risk,
          design_fingerprint = operation.technology_design.design_fingerprint})
      })
    elseif rejected then
      table.insert(candidates, rejected)
    end
  end
  table.sort(candidates, function(left, right) return left.candidate_id < right.candidate_id end)
  return plan, candidates
end

return M
