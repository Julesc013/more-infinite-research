local C = require("prototypes.mir.streams.registry")
local D = require("prototypes.mir.report.diagnostics_sink")
local deepcopy = require("prototypes.mir.core.deepcopy")
local table_utils = require("prototypes.mir.core.table")
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
local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local target_line = require("prototypes.mir.platform.factorio.target_line")
local effect_scaling = require("prototypes.mir.settings.effect_scaling")
local generation_plan = require("prototypes.mir.planner.generation_plan")
local family_resolver = require("prototypes.mir.families.resolver")
local family_registry = require("prototypes.mir.families.registry")
local provider_registry = require("prototypes.mir.providers.registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local recipe_risk_facts = require("prototypes.mir.index.recipe_risk_facts")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local automatic_compiler_policy = require("prototypes.mir.settings.automatic_compiler_policy")
local compatibility_policy = require("prototypes.mir.compatibility.policy_authority")
local effect_ownership = require("prototypes.mir.planner.effect_ownership")
local native_owner_contract = require("prototypes.mir.domain.native_owner.contract")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_catalog = require("prototypes.mir.planner.technology_catalog")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local technology_selection_policy = require("prototypes.mir.planner.technology_selection_policy")

local M = {}

local GATE_EVIDENCE = {
  target_supported = {evaluator = "target-profile", evidence = "positive-feature-contract", initial = "passed"},
  effect_valid = {evaluator = "effect-contracts", initial = "pending"},
  owner_conflict_free = {evaluator = "owner-policy", evidence = "no-blocking-owner", initial = "passed"},
  science_compatible = {evaluator = "science-selector", evidence = "resolved-ingredients", initial = "passed"},
  lab_compatible = {evaluator = "lab-compatibility", evidence = "accepted-ingredient-set", initial = "passed"},
  prerequisites_acyclic = {evaluator = "technology-graph", initial = "pending"},
  loop_safe = {evaluator = "recipe-risk-facts", evidence = "fail-closed-risk-filter", initial = "passed"},
  progression_safe = {evaluator = "technology-graph", initial = "pending"},
  migration_safe = {evaluator = "stream-manifest", evidence = "stable-identity", initial = "passed"},
  output_identity_safe = {evaluator = "generation-plan", initial = "pending"}
}

local function proof_gates(action, failed_gates)
  local out = {}
  for gate_name, contract in pairs(GATE_EVIDENCE) do
    if failed_gates and failed_gates[gate_name] then
      local failure = failed_gates[gate_name]
      out[gate_name] = gate_contract.failed(
        failure.evaluator or contract.evaluator,
        failure.reason,
        {failure.evidence}
      )
    elseif action == "skip" then
      out[gate_name] = gate_contract.not_applicable(
        "generation-plan",
        "candidate-action-is-materializing",
        fingerprint.of({action = action, gate = gate_name}),
        {"decision:non-materializing-row"}
      )
    elseif contract.initial == "pending" then
      out[gate_name] = gate_contract.pending(contract.evaluator)
    else
      out[gate_name] = gate_contract.passed(contract.evaluator, {contract.evidence})
    end
  end
  return out
end

local function lname(key, spec)
  if spec.localised_name then return spec.localised_name end
  local locale_key = "technology-name.more-infinite-research."..key
  local out = {locale_key}
  if spec.icon_item then
    table.insert(out, {"item-name."..spec.icon_item})
  elseif spec.icon_fluid then
    table.insert(out, {"fluid-name."..spec.icon_fluid})
  elseif spec.items and #spec.items == 1 then
    table.insert(out, {"item-name."..spec.items[1]})
  elseif spec.fluids and #spec.fluids == 1 then
    table.insert(out, {"fluid-name."..spec.fluids[1]})
  elseif spec.icon_tech then
    table.insert(out, {"technology-name."..spec.icon_tech})
  end
  return out
end

local function ldesc(spec)
  if spec.localised_description then return spec.localised_description end
  if spec.description_locale_key then return { spec.description_locale_key } end
  if spec.direct_effects then
    return {"technology-description.more-infinite-research.direct_effect"}
  end
  return {"technology-description.more-infinite-research.recipe_productivity"}
end

local function append_unique_item(items, seen, item_name)
  if item_name and not seen[item_name] then
    seen[item_name] = true
    table.insert(items, item_name)
  end
end

local function expand_dynamic_items(spec)
  if not (spec and spec.dynamic_items_from_lab_inputs) then return spec end

  local out = deepcopy(spec)

  local base_group_items = {}
  for _, item_name in ipairs(out.items or {}) do
    table.insert(base_group_items, item_name)
  end

  if not out.groups then
    out.groups = {
      {
        change = C.shared.per_level_default,
        items = base_group_items
      }
    }
  end
  if not out.groups[1] then
    out.groups[1] = {
      change = C.shared.per_level_default,
      items = base_group_items
    }
  end
  out.groups[1].items = out.groups[1].items or {}

  local first_group_seen = {}
  for _, item_name in ipairs(out.groups[1].items) do
    first_group_seen[item_name] = true
  end
  for _, item_name in ipairs(base_group_items) do
    append_unique_item(out.groups[1].items, first_group_seen, item_name)
  end

  local seen = {}
  for _, item_name in ipairs(out.items or {}) do
    seen[item_name] = true
  end
  for _, group in ipairs(out.groups or {}) do
    for _, item_name in ipairs(group.items or {}) do
      seen[item_name] = true
    end
  end

  for _, item_name in ipairs(science_packs.pack_list_all()) do
    append_unique_item(out.groups[1].items, seen, item_name)
  end

  return out
end

local function plan_row(key, spec, action, reason, diagnostics, extra)
  extra = extra or {}
  local row = {
    schema = 3,
    manifest_id = spec.manifest_id or key,
    stream_key = key,
    action = action,
    reason = reason,
    source = spec.automatic_family and "family-rule" or "fixed-stream",
    provider_ids = family_resolver.provider_ids_for_stream(key),
    family_ids = family_resolver.family_ids_for_stream(key),
    provider_decision_fingerprints = family_resolver.decision_fingerprints_for_stream(key),
    risk_fingerprints = family_resolver.risk_fingerprints_for_stream(key),
    spec = spec,
    diagnostics = diagnostics,
    gates = proof_gates(action, extra.failed_gates)
  }
  for field, value in pairs(extra) do
    if field ~= "failed_gates" then row[field] = value end
  end
  return row
end

local function skip_row(key, spec, reason, ingredients, effects, lab_status, extra, failed_gates)
  local diagnostics_extra = extra
  extra = extra or {}
  extra.failed_gates = failed_gates
  return plan_row(
    key,
    spec,
    "skip",
    reason,
    D.stream_fields(key, spec, "skipped", reason, ingredients, nil, effects, lab_status, diagnostics_extra),
    extra
  )
end

local function attach_family_recipes(key, buckets)
  local policy = automatic_compiler_policy.current()
  if not policy.apply_changes then return buckets end
  local attachments = family_resolver.attachments_for_stream(key)
  if #attachments == 0 then return buckets end

  local assigned, buckets_by_change = {}, {}
  for _, bucket in ipairs(buckets or {}) do
    buckets_by_change[bucket.change] = bucket
    for _, recipe_name in ipairs(bucket.recipes or {}) do assigned[recipe_name] = true end
  end
  for _, attachment in ipairs(attachments) do
    if not assigned[attachment.recipe] then
      local bucket = buckets_by_change[attachment.change]
      if not bucket then
        bucket = {change = attachment.change, recipes = {}}
        buckets_by_change[attachment.change] = bucket
        table.insert(buckets, bucket)
      end
      table.insert(bucket.recipes, attachment.recipe)
      assigned[attachment.recipe] = true
    end
  end
  for _, bucket in ipairs(buckets or {}) do table.sort(bucket.recipes) end
  return buckets
end

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

  local base_cost = costs.base_cost_for(key, spec)
  local growth_factor = costs.growth_factor_for(key, spec)
  local max_level = costs.max_level_for(key, spec)
  local count_formula = tostring(base_cost) .. "*" .. tostring(growth_factor) .. "^(L-1)"
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
      ingredients = ingredients,
      research_time = research_time,
      max_level = max_level,
    }
    return plan_row(key, spec, "emit", "direct_effect",
      D.stream_fields(key, spec, "generated", "direct_effect", ingredients, prerequisites, emitted_effects, lab_status), {
        technology_name = spec.technology_name or ("recipe-prod-" .. key .. "-1"),
        fields = fields,
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
    ingredients = ingredients,
    research_time = research_time,
    max_level = max_level,
  }
  return plan_row(key, spec, "emit", "recipe_productivity",
    D.stream_fields(key, spec, "generated", "recipe_productivity", ingredients, prerequisites, emitted_effects, lab_status), {
      technology_name = spec.technology_name or ("recipe-prod-" .. key .. "-1"),
      fields = fields,
      direct_effects = false
    })
end

local function compile_active(context, return_view)
  science_packs.ensure_services(context)
  local cached = context:state_view("generation_plan")
  if cached then return return_view and cached or deepcopy(cached) end
  telemetry.start_phase("stream_compiler")
  local streams = C.snapshot()
  local native_owner_inputs = {}
  for key, spec in pairs(streams) do
    local binding = spec.native_owner_binding
    if binding and binding.owner then
      local owner = data_raw.technology(binding.owner)
      native_owner_inputs[key] = owner and native_owner_contract.snapshot(owner)
        or {name = binding.owner, missing = true}
    end
  end
  local plan = generation_plan.new({
    source_fingerprints = {
      facts = recipe_facts.fingerprint(),
      risks = recipe_risk_facts.fingerprint(),
      rules = fingerprint.of({streams = streams, families = family_registry.snapshot()}),
      providers = provider_registry.fingerprint(),
      compatibility_packs = fingerprint.of(compatibility_policy.active_packs()),
      target_profile = fingerprint.of(target_profiles.current()),
      native_owners = fingerprint.of(native_owner_inputs),
      provider_decisions = family_resolver.snapshot().decision_set_fingerprint
    }
  })
  local rows = {}
  for _, key in ipairs(table_utils.sorted_keys(streams)) do
    table.insert(rows, plan_stream(key, streams[key]))
  end
  rows = effect_ownership.resolve(rows, {defer_design_refresh = true})
  local catalog = technology_catalog.from_preselection_rows(
    rows,
    plan.source_fingerprints,
    {trusted_designs = true}
  )
  catalog = technology_catalog.bind_selections(catalog, rows)
  technology_selection_policy.assert_generation_projection(catalog.current_selections, rows)
  for _, row in ipairs(rows) do
    row.technology_design = technology_design.from_generation_row(row)
    plan:add_owned_derived(row)
  end
  local finalized = plan:finalize()
  local artifact = finalized:artifact_view()
  catalog = technology_catalog.bind_selections(catalog, artifact.rows)
  technology_selection_policy.assert_generation_projection(catalog.current_selections, artifact.rows)
  telemetry.count("stream_rows", #artifact.rows)
  telemetry.finish_phase("stream_compiler")
  telemetry.count("technology_catalog_candidates", #catalog.candidates)
  telemetry.count("technology_catalog_alternatives", #catalog.alternative_qualifications)
  telemetry.count("technology_catalog_canonical_bytes", #fingerprint.canonical(catalog))
  -- The preselection catalog is deliberately transient. CompilationPlan owns
  -- the one canonical schema-3 catalog after sanitation and graph decisions.
  context:set_state("generation_plan", artifact)
  return return_view and artifact or deepcopy(artifact)
end

local function compile(context, return_view)
  context = context or compiler_context.current()
  return compiler_context.with_active(context, compile_active, context, return_view)
end

function M.compile(context)
  return compile(context, false)
end

function M.compile_view(context)
  return compile(context, true)
end

function M.accept(plan, context)
  context = context or compiler_context.current()
  local artifact = type(plan.artifact) == "function" and plan:artifact() or deepcopy(plan)
  if context:has_state("generation_plan") then
    context:replace_epoch("generation_plan", artifact, context:state_epoch("generation_plan"))
  else
    context:set_state("generation_plan", artifact)
  end
end

function M.latest_artifact(context)
  context = context or compiler_context.current()
  return context:state_snapshot("generation_plan")
end

function M.accept_artifact(artifact, context, options)
  context = context or compiler_context.current()
  local accepted = options and options.trusted and artifact or deepcopy(artifact)
  if context:has_state("generation_plan") then
    context:replace_epoch("generation_plan", accepted, context:state_epoch("generation_plan"))
  else
    context:set_state("generation_plan", accepted)
  end
end

function M.assert_output(context)
  return require("prototypes.mir.planner.output_validator").assert_artifact(M.latest_artifact(context))
end

return M
