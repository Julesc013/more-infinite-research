local D = require("prototypes.mir.report.diagnostics_sink")
local contract = require("prototypes.mir.capabilities.contract")
local fact_registry = require("prototypes.mir.index.registry_builder")
local policies = require("prototypes.mir.policy.capabilities")
local schema = require("prototypes.mir.core.schema")
local deepcopy = require("prototypes.mir.core.deepcopy")
local family_resolver = require("prototypes.mir.families.resolver")
local native_effect_coverage = require("prototypes.mir.policy.native_effect_coverage")

local C = {}

-- Capability resolvers are report-first. They classify prototype evidence and
-- explain how existing MIR streams treat it; they do not emit technologies.

local NATIVE_MODIFIERS = {
  ["gun-speed"] = {
    subfamily = "weapon_firing_speed",
    request_id = "NATIVE-01",
    semantic_scope = "ammo-category-firing-rate",
    semantic_exclusions = "ammo-damage,ammo-stack-size,energy-capacity,recipe-productivity",
    useful_level_status = "positive-effect-and-owner-identity-only",
    paid_noop_guard = "positive-effect-and-single-owner-required",
    required_proof = "exact-engine-ammo-throughput-and-energy-observation",
    throughput_disposition = "not-proven-by-static-analysis"
  },
  ["belt-stack-size-bonus"] = {
    subfamily = "belt_stack_size",
    request_id = "STACK-02",
    semantic_scope = "belt-lane-item-stack-size",
    semantic_exclusions = "item-stack-size,character-inventory-slots,character-reach,pipeline-extent,underground-belt-distance",
    useful_level_status = "withheld-until-exact-transport-cap-proof",
    paid_noop_guard = "no-mir-emission-without-cap-and-conservation-proof",
    required_proof = "exact-engine-visual-transport-throughput-and-conservation"
  },
  ["inserter-stack-size-bonus"] = {
    subfamily = "inserter_stack_size",
    request_id = "STACK-02",
    semantic_scope = "inserter-held-item-stack-size",
    semantic_exclusions = "belt-stack-size,item-stack-size,character-inventory-slots,character-reach,pipeline-extent,underground-belt-distance",
    useful_level_status = "withheld-until-exact-transport-cap-proof",
    paid_noop_guard = "no-mir-emission-without-cap-and-conservation-proof",
    required_proof = "exact-engine-inserter-loader-splitter-and-conservation",
    current_mir_base_continuation = "unqualified-pending-exact-cap-and-conservation-proof"
  },
  ["stack-inserter-capacity-bonus"] = {
    subfamily = "inserter_stack_size",
    request_id = "STACK-02",
    semantic_scope = "stack-inserter-held-item-capacity",
    semantic_exclusions = "belt-stack-size,item-stack-size,character-inventory-slots,character-reach,pipeline-extent,underground-belt-distance",
    useful_level_status = "withheld-until-exact-transport-cap-proof",
    paid_noop_guard = "no-mir-emission-without-cap-and-conservation-proof",
    required_proof = "exact-engine-inserter-loader-splitter-and-conservation",
    current_mir_base_continuation = "unqualified-pending-exact-cap-and-conservation-proof"
  },
  ["bulk-inserter-capacity-bonus"] = {
    subfamily = "inserter_stack_size",
    request_id = "STACK-02",
    semantic_scope = "bulk-inserter-held-item-capacity",
    semantic_exclusions = "belt-stack-size,item-stack-size,character-inventory-slots,character-reach,pipeline-extent,underground-belt-distance",
    useful_level_status = "withheld-until-exact-transport-cap-proof",
    paid_noop_guard = "no-mir-emission-without-cap-and-conservation-proof",
    required_proof = "exact-engine-inserter-loader-splitter-and-conservation",
    current_mir_base_continuation = "unqualified-pending-exact-cap-and-conservation-proof"
  },
  ["laboratory-productivity"] = {subfamily = "science_modifier"},
  ["laboratory-speed"] = {subfamily = "science_modifier"},
  ["mining-drill-productivity-bonus"] = {subfamily = "native_mining_yield"},
  ["worker-robot-battery"] = {subfamily = "robot_modifier"},
  ["worker-robot-speed"] = {subfamily = "robot_modifier"},
  ["worker-robot-storage"] = {subfamily = "robot_modifier"}
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

local function new_native_owner_row(effect_type, policy)
  return {
    effect_type = effect_type,
    subfamily = policy.subfamily,
    policy = policy,
    technologies = {}, technologies_seen = {},
    subjects = {}, subjects_seen = {},
    qualified_technologies = {}, qualified_technologies_seen = {},
    unqualified_technologies = {}, unqualified_technologies_seen = {},
    mir_base_continuation_technologies = {}, mir_base_continuation_technologies_seen = {},
    mir_stream = 0,
    mir_base_continuation = 0,
    external = 0,
    qualified_external = 0,
    qualified = 0,
    unqualified_sightings = 0,
    unqualified_reasons = {}, unqualified_reasons_seen = {}
  }
end

-- Registry ownership is only a sighting until the same positive,
-- enabled/reachable-infinite identity predicate used by direct ownership
-- accepts it. This prevents a finite, disabled, zero-value, or
-- science-unreachable technology from becoming diagnostic coverage.
local function native_owner_summary(registry)
  local by_effect = {}

  for _, owner in ipairs(registry.owners or {}) do
    local policy = NATIVE_MODIFIERS[owner.effect_type]
    if policy then
      by_effect[owner.effect_type] = by_effect[owner.effect_type]
        or new_native_owner_row(owner.effect_type, policy)
      local row = by_effect[owner.effect_type]
      push_unique(row.technologies, row.technologies_seen, owner.technology)
      push_unique(row.subjects, row.subjects_seen, owner.subject)

      local is_mir_stream = owner.mod_owner == "more-infinite-research"
      local is_mir_base_continuation = owner.policy == "native_continuation_owner"
      if is_mir_base_continuation then
        row.mir_base_continuation = row.mir_base_continuation + 1
        push_unique(row.mir_base_continuation_technologies,
          row.mir_base_continuation_technologies_seen, owner.technology)
      elseif is_mir_stream then
        row.mir_stream = row.mir_stream + 1
      else
        row.external = row.external + 1
      end

      local qualification_reason = native_effect_coverage.technology_effect_identity_qualification_reason(
        owner.technology, owner.effect, {positive_numeric_value = true})
      if qualification_reason == nil then
        row.qualified = row.qualified + 1
        push_unique(row.qualified_technologies, row.qualified_technologies_seen, owner.technology)
        if not is_mir_stream and not is_mir_base_continuation then
          row.qualified_external = row.qualified_external + 1
        end
      else
        row.unqualified_sightings = row.unqualified_sightings + 1
        push_unique(row.unqualified_technologies, row.unqualified_technologies_seen, owner.technology)
        push_unique(row.unqualified_reasons, row.unqualified_reasons_seen, qualification_reason)
      end
    end
  end

  return by_effect
end

local function emit_native_modifier_decisions(registry, resolver, discovered_rows)
  local rows = discovered_rows or native_owner_summary(registry)
  local total = 0
  local warnings = 0

  for _, effect_type in ipairs(sorted_keys(NATIVE_MODIFIERS)) do
    local policy = NATIVE_MODIFIERS[effect_type]
    local row = rows[effect_type] or new_native_owner_row(effect_type, policy)
    total = total + 1
    if row.qualified_external > 0 then warnings = warnings + 1 end

    local observed = row.qualified
    local reason
    local decision
    local emitted = "false"
    local policy_name = "diagnose_only"
    local current_emission_status = "none"
    if policy.current_mir_base_continuation and row.mir_base_continuation > 0 then
      reason = "existing_mir_base_continuation_pending_exact_cap_and_conservation_proof"
      decision = "report_existing_mir_base_continuation_pending_exact_proof"
      emitted = "true"
      policy_name = "existing-mir-base-continuation-unqualified"
      current_emission_status = policy.current_mir_base_continuation
    elseif observed == 0 then
      reason = row.unqualified_sightings > 0 and "unqualified_native_modifier_sighting"
        or "native_modifier_not_observed"
    elseif row.qualified_external > 0 then
      reason = "native_modifier_external_owner_observed"
    else
      reason = "native_modifier_mir_owner_observed"
    end
    if not decision then
      decision = observed > 0 and "observe_existing_owner" or "withhold_until_exact_observation"
    end
    if emitted == "false" and row.mir_stream > 0 then
      emitted = "true"
      current_emission_status = "existing-mir-stream-observed"
    end
    local confidence = observed > 0 and "owner=1,total=1" or "owner=0,total=0"
    local blocker = policy.required_proof or ""
    local risk = observed > 0 and row.qualified_external > 0 and "duplicate_native_modifier_owner" or ""
    if policy.paid_noop_guard then
      risk = risk ~= "" and (risk .. "," .. policy.paid_noop_guard) or policy.paid_noop_guard
    end

    D.decision({
      key = effect_type,
      status = "diagnostic",
      reason = reason,
      subject_type = "modifier",
      subject = effect_type,
      capability = resolver.id,
      family = resolver.family,
      subfamily = row.subfamily,
      confidence = confidence,
      source = resolver.source,
      policy = observed > 0 and row.qualified_external > 0 and "prefer_existing_owner" or policy_name,
      decision = decision,
      emitted = emitted,
      blockers = blocker,
      risks = risk,
      technologies = join_names(row.technologies),
      target = join_names(row.subjects),
      evidence = "technology_effect_type:" .. effect_type,
      total = tostring(observed),
      raw_sightings = tostring(#row.technologies),
      unqualified_sightings = tostring(row.unqualified_sightings),
      qualified_technologies = join_names(row.qualified_technologies),
      unqualified_technologies = join_names(row.unqualified_technologies),
      unqualified_reasons = join_names(row.unqualified_reasons),
      mir_owned = tostring(row.mir_stream),
      mir_base_continuation = tostring(row.mir_base_continuation),
      mir_base_continuation_technologies = join_names(row.mir_base_continuation_technologies),
      external_owned_unknown = tostring(row.external),
      qualified_external_owners = tostring(row.qualified_external),
      request_id = policy.request_id or "",
      semantic_scope = policy.semantic_scope or "",
      semantic_exclusions = policy.semantic_exclusions or "",
      useful_level_status = policy.useful_level_status or "not-applicable",
      paid_noop_guard = policy.paid_noop_guard or "",
      throughput_disposition = policy.throughput_disposition or "",
      current_emission_status = current_emission_status
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
    row.decision = row.qualified > 0 and "observe_existing_owner" or "withhold_until_exact_observation"
    row.has_conflict = row.qualified_external > 0
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
