local D = require("prototypes.mir.report.diagnostics_sink")
local contract = require("prototypes.mir.capabilities.contract")
local fact_registry = require("prototypes.mir.index.registry_builder")
local policies = require("prototypes.mir.policy.capabilities")
local schema = require("prototypes.mir.core.schema")
local deepcopy = require("prototypes.mir.core.deepcopy")
local family_resolver = require("prototypes.mir.families.resolver")

local C = {}

-- Capability resolvers are report-first. They classify prototype evidence and
-- explain how existing MIR streams treat it; they do not emit technologies.

local NATIVE_MODIFIERS = {
  ["belt-stack-size-bonus"] = "native_logistics_modifier",
  ["inserter-stack-size-bonus"] = "native_logistics_modifier",
  ["laboratory-productivity"] = "science_modifier",
  ["laboratory-speed"] = "science_modifier",
  ["mining-drill-productivity-bonus"] = "native_mining_yield",
  ["worker-robot-battery"] = "robot_modifier",
  ["worker-robot-speed"] = "robot_modifier",
  ["worker-robot-storage"] = "robot_modifier"
}

local RESOLVERS = {
  {
    id = "logistics-loader-manufacturing",
    schema_version = schema.capability_resolver,
    family = "logistics_item",
    subfamily = "loader",
    source = "capability:loader-resolver",
    policy = "existing_stream_or_report",
    policy_config = policies.for_capability("logistics-loader-manufacturing")
  },
  {
    id = "mining-drill-manufacturing",
    schema_version = schema.capability_resolver,
    family = "machine_manufacturing",
    subfamily = "mining_drill",
    source = "capability:mining-drill-resolver",
    policy = "existing_stream_or_report",
    policy_config = policies.for_capability("mining-drill-manufacturing")
  },
  {
    id = "native-modifier-ownership",
    schema_version = schema.capability_resolver,
    family = "native_modifier",
    subfamily = "owner_registry",
    source = "capability:native-modifier-resolver",
    policy = "diagnose_only",
    policy_config = policies.for_capability("native-modifier-ownership")
  }
}

local CANONICAL_RULES = {
  ["logistics-loader-manufacturing"] = { ["loader-manufacturing"] = true },
  ["mining-drill-manufacturing"] = { ["mining-drill-manufacturing"] = true }
}

local function sorted_keys(tbl)
  return fact_registry.sorted_keys(tbl or {})
end

local function push_unique(list, seen, value)
  if value and not seen[value] then
    seen[value] = true
    table.insert(list, value)
  end
end

local function join_names(list)
  local copy = {}
  for _, value in ipairs(list or {}) do
    table.insert(copy, tostring(value))
  end
  table.sort(copy)
  return table.concat(copy, ",")
end

local function format_bool(value)
  if value then return "true" end
  return "false"
end

local function emit_recipe_capability_decisions(registry, resolver, classified_candidates)
  local generated = 0
  local proposed = 0
  local diagnosed = 0
  local candidates = classified_candidates or {}

  for _, candidate in ipairs(candidates) do
      local row = candidate.provider_decision
      local emitted = row.decision == "attach"
      if emitted then generated = generated + 1
      elseif row.decision == "propose" then proposed = proposed + 1
      else diagnosed = diagnosed + 1 end
      D.decision({
        key = row.recipe,
        status = "diagnostic",
        reason = "canonical_provider_decision_projection",
        subject_type = "recipe",
        subject = row.recipe,
        capability = resolver.id,
        family = row.rule,
        subfamily = resolver.subfamily,
        confidence = row.risk_disposition == "PASS" and "family=1,owner=1,total=1" or "family=1,owner=1,total=0.75",
        source = "provider-decision:" .. row.provider_id,
        policy = row.policy_scope,
        decision = row.decision,
        emitted = format_bool(emitted),
        blockers = row.blocker or "",
        risks = join_names(row.risk_hard_flags) .. (#(row.risk_review_flags or {}) > 0 and "," .. join_names(row.risk_review_flags) or ""),
        stable_stream_id = emitted and (row.target_stream or "") or "",
        recipe = row.recipe,
        recipes = row.recipe,
        target = row.item,
        effect = "change-recipe-productivity",
        evidence = join_names((row.diagnostic_provenance or {}).evidence),
        provider_id = row.provider_id,
        decision_fingerprint = row.decision_fingerprint,
        planner_decision_fingerprint = row.decision_fingerprint,
        risk_fingerprint = row.risk_fingerprint,
        risk_disposition = row.risk_disposition,
        cardinality_fingerprint = row.cardinality and row.cardinality.cardinality_fingerprint
      })
  end
    D.compatibility_plan({
      key = "capability:" .. resolver.id,
      status = "diagnostic",
      reason = "canonical_provider_decision_summary",
      capability = resolver.id,
      family = resolver.family,
      subfamily = resolver.subfamily,
      total = tostring(#candidates),
      generated = tostring(generated),
      unknown = tostring(proposed),
      warnings = tostring(diagnosed),
      evidence = "FamilyRule.ProviderDecision"
    })
  return #candidates, generated, proposed, diagnosed
end

local function native_owner_summary(registry)
  local by_effect = {}

  for _, owner in ipairs(registry.owners or {}) do
    local subfamily = NATIVE_MODIFIERS[owner.effect_type]
    if subfamily then
      by_effect[owner.effect_type] = by_effect[owner.effect_type] or {
        effect_type = owner.effect_type,
        subfamily = subfamily,
        technologies = {},
        technologies_seen = {},
        mir = 0,
        external = 0
      }

      local row = by_effect[owner.effect_type]
      push_unique(row.technologies, row.technologies_seen, owner.technology)
      if owner.mod_owner == "more-infinite-research" then
        row.mir = row.mir + 1
      else
        row.external = row.external + 1
      end
    end
  end

  return by_effect
end

local function emit_native_modifier_decisions(registry, resolver, discovered_rows)
  local rows = discovered_rows or native_owner_summary(registry)
  local total = 0
  local warnings = 0

  for _, effect_type in ipairs(sorted_keys(rows)) do
    local row = rows[effect_type]
    total = total + 1
    if row.external > 0 then warnings = warnings + 1 end

    D.decision({
      key = effect_type,
      status = "diagnostic",
      reason = row.external > 0 and "native_modifier_external_owner_observed" or "native_modifier_mir_owner_observed",
      subject_type = "modifier",
      subject = effect_type,
      capability = resolver.id,
      family = resolver.family,
      subfamily = row.subfamily,
      confidence = "owner=1,total=1",
      source = resolver.source,
      policy = row.external > 0 and "prefer_existing_owner" or resolver.policy,
      decision = "observe_existing_owner",
      emitted = "false",
      blockers = row.external > 0 and "external_native_modifier_owner" or "",
      risks = row.external > 0 and "duplicate_native_modifier_owner" or "",
      technologies = join_names(row.technologies),
      evidence = "technology_effect_type:" .. effect_type,
      total = tostring(row.mir + row.external),
      mir_owned = tostring(row.mir),
      external_owned_unknown = tostring(row.external)
    })
  end

  D.compatibility_plan({
    key = "capability:" .. resolver.id,
    status = "diagnostic",
    reason = "native_modifier_ownership_summary",
    capability = resolver.id,
    family = resolver.family,
    subfamily = resolver.subfamily,
    total = tostring(total),
    warnings = tostring(warnings),
    evidence = "technology_effect_scan"
  })

  return total, 0, 0, warnings
end

local function emit_family_rule_decisions(excluded_rules)
  local rows = family_resolver.snapshot().decisions
  local attached, proposed, diagnosed, total = 0, 0, 0, 0
  for _, row in ipairs(rows) do
    if not (excluded_rules and excluded_rules[row.rule]) then
    total = total + 1
    if row.decision == "attach" then attached = attached + 1
    elseif row.decision == "propose" then proposed = proposed + 1
    else diagnosed = diagnosed + 1 end
    D.decision({
      key = row.recipe,
      status = "diagnostic",
      reason = "semantic_family_rule_decision",
      subject_type = "recipe",
      capability = row.capability,
      family = row.rule,
      source = "family-rule:" .. row.rule,
      policy = "attach-existing-only",
      decision = row.decision,
      emitted = row.decision == "attach" and "true" or "false",
      blockers = row.blocker or "",
      stable_stream_id = row.target_stream or "",
      recipe = row.recipe,
      target = row.item,
      effect = "change-recipe-productivity",
      evidence = "recipe-output:item-place-result:entity-type",
      provider_id = row.provider_id,
      decision_fingerprint = row.decision_fingerprint,
      planner_decision_fingerprint = row.decision_fingerprint,
      risk_fingerprint = row.risk_fingerprint,
      risk_disposition = row.risk_disposition,
      cardinality_fingerprint = row.cardinality and row.cardinality.cardinality_fingerprint
    })
    end
  end
  D.compatibility_plan({
    key = "family_rule_registry",
    status = "diagnostic",
    reason = "semantic_family_rules_resolved",
    capability = "recipe-productivity",
    total = tostring(total),
    generated = tostring(attached),
    unknown = tostring(proposed),
    warnings = tostring(diagnosed),
    evidence = "RecipeFactV2,relationship-index,FamilyRule"
  })
end

local function require_stage(state, expected, next_stage)
  if type(state) ~= "table" or state.stage ~= expected then
    error("MIR capability lifecycle expected " .. expected .. " state.", 3)
  end
  state.stage = next_stage
  return state
end

local function discover_recipe_state(registry, resolver)
  local candidates = {}
  local wanted_rules = CANONICAL_RULES[resolver.id] or {}
  for _, row in ipairs(family_resolver.snapshot().decisions or {}) do
    if wanted_rules[row.rule] then table.insert(candidates, {provider_decision = row}) end
  end
  return {
    stage = "discovered",
    registry = registry,
    resolver = resolver,
    candidates = candidates
  }
end

local function classify_recipe_state(state)
  require_stage(state, "discovered", "classified")
  for _, candidate in ipairs(state.candidates) do
    local row = candidate.provider_decision
    candidate.recipe = row.recipe
    candidate.item = row.item
    candidate.decision = row.decision
    candidate.emitted = row.decision == "attach"
    candidate.blockers = row.blocker
    candidate.risks = deepcopy(row.risk_hard_flags or {})
    for _, risk in ipairs(row.risk_review_flags or {}) do table.insert(candidate.risks, risk) end
  end
  return state
end

local function propose_recipe_state(state)
  require_stage(state, "classified", "proposed")
  for _, candidate in ipairs(state.candidates) do candidate.proposal = candidate.decision end
  return state
end

local function validate_recipe_state(state)
  require_stage(state, "proposed", "validated")
  for _, candidate in ipairs(state.candidates) do
    candidate.valid = candidate.item ~= nil
      and candidate.recipe ~= nil
      and candidate.proposal ~= nil
      and candidate.provider_decision ~= nil
    if not candidate.valid then error("Invalid entity-backed capability candidate.", 2) end
  end
  return state
end

local function materialize_recipe_state(state)
  require_stage(state, "validated", "materialized")
  state.result = {emit_recipe_capability_decisions(
    state.registry,
    state.resolver,
    state.candidates
  )}
  return state
end

local function recipe_result(state)
  require_stage(state, "materialized", "result")
  return state.result
end

local function discover_native_state(registry, resolver)
  return {stage = "discovered", registry = registry, resolver = resolver, rows = native_owner_summary(registry)}
end

local function classify_native_state(state)
  require_stage(state, "discovered", "classified")
  for _, row in pairs(state.rows) do
    row.decision = "observe_existing_owner"
    row.has_conflict = row.external > 0
  end
  return state
end

local function propose_native_state(state)
  return require_stage(state, "classified", "proposed")
end

local function validate_native_state(state)
  require_stage(state, "proposed", "validated")
  for effect_type, row in pairs(state.rows) do
    if row.effect_type ~= effect_type or not row.decision then
      error("Invalid native modifier ownership capability row.", 2)
    end
  end
  return state
end

local function materialize_native_state(state)
  require_stage(state, "validated", "materialized")
  state.result = {emit_native_modifier_decisions(state.registry, state.resolver, state.rows)}
  return state
end

local function native_result(state)
  require_stage(state, "materialized", "result")
  return state.result
end

local function configure_resolvers()
  RESOLVERS[1].discover = function(registry)
    return discover_recipe_state(registry, RESOLVERS[1], {loader = true, ["loader-1x1"] = true})
  end
  RESOLVERS[1].classify = classify_recipe_state
  RESOLVERS[1].propose = propose_recipe_state
  RESOLVERS[1].validate = validate_recipe_state
  RESOLVERS[1].materialize = materialize_recipe_state
  RESOLVERS[1].result = recipe_result

  RESOLVERS[2].discover = function(registry)
    return discover_recipe_state(registry, RESOLVERS[2], {["mining-drill"] = true})
  end
  RESOLVERS[2].classify = classify_recipe_state
  RESOLVERS[2].propose = propose_recipe_state
  RESOLVERS[2].validate = validate_recipe_state
  RESOLVERS[2].materialize = materialize_recipe_state
  RESOLVERS[2].result = recipe_result

  RESOLVERS[3].discover = function(registry) return discover_native_state(registry, RESOLVERS[3]) end
  RESOLVERS[3].classify = classify_native_state
  RESOLVERS[3].propose = propose_native_state
  RESOLVERS[3].validate = validate_native_state
  RESOLVERS[3].materialize = materialize_native_state
  RESOLVERS[3].result = native_result
end

configure_resolvers()

function C.resolvers()
  return contract.validate_all(RESOLVERS)
end

function C.emit(registry)
  if not D.enabled() then return end

  local total = 0
  local generated = 0
  local proposed = 0
  local warnings = 0

  local resolvers = C.resolvers()
  for _, resolver in ipairs(resolvers) do
    local state = resolver.discover(registry)
    state = resolver.classify(state)
    state = resolver.propose(state)
    state = resolver.validate(state)
    state = resolver.materialize(state)
    local result = resolver.result(state)
    total = total + result[1]
    generated = generated + result[2]
    proposed = proposed + result[3]
    warnings = warnings + result[4]
  end

  emit_family_rule_decisions({
    ["loader-manufacturing"] = true,
    ["mining-drill-manufacturing"] = true
  })

  D.compatibility_plan({
    key = "capability_registry",
    status = "diagnostic",
    reason = "capability_resolvers_reported",
    capability = "registry",
    total = tostring(total),
    generated = tostring(generated),
    unknown = tostring(proposed),
    warnings = tostring(warnings),
    evidence = "discover,classify,propose,validate,materialize,result"
  })
end

return C
