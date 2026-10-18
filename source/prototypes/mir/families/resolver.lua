local deepcopy = require("prototypes.mir.core.deepcopy")
local relationships = require("prototypes.mir.index.relationships")
local rule_registry = require("prototypes.mir.families.registry")
local policy_authority = require("prototypes.mir.compatibility.policy_authority")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local operator_dsl = require("prototypes.mir.families.operator_dsl")
local fingerprint = require("prototypes.mir.core.fingerprint")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local provider_discovery = require("prototypes.mir.providers.pipeline.discovery")
local provider_normalization = require("prototypes.mir.providers.pipeline.normalization")
local provider_classification = require("prototypes.mir.providers.pipeline.classification")
local provider_pack_policy = require("prototypes.mir.providers.pipeline.pack_policy")
local provider_hazard_policy = require("prototypes.mir.providers.pipeline.hazard_policy")
local provider_owner_arbitration = require("prototypes.mir.providers.pipeline.owner_arbitration")
local provider_decision = require("prototypes.mir.providers.pipeline.decision")
local provider_claim = require("prototypes.mir.providers.pipeline.provider_claim")
local provider_budget = require("prototypes.mir.providers.pipeline.budget")
local provider_metrics = require("prototypes.mir.providers.provider_metrics")
local researchability_index = require("prototypes.mir.graph.researchability_index")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local environment_adapter = require("prototypes.mir.platform.factorio.environment_identity")
local environment_identity = require("prototypes.mir.domain.environment_identity")

local M = {}

local HARD_BLOCKERS = {
  recipe_fact_missing = true,
  recycling_loop = true,
  hidden_internal = true,
  productivity_disabled = true,
  catalyst_or_self_return = true,
  non_deterministic_output = true,
  ambiguous_placeable_output = true,
  recipe_productivity_not_allowed = true,
  variant_productivity_not_allowed = true,
  zero_productivity_cap = true,
  variant_zero_productivity_cap = true,
  parameter_recipe = true,
  recycling_recipe = true,
  self_return_risk = true,
  non_exclusive_placeable_output = true,
  non_productive_placeable_output = true,
  non_deterministic_placeable_output = true,
  existing_recipe_productivity_owner = true
}

local function apply_cardinality_guard(rows, limits, candidate_count)
  return provider_budget.apply(rows, limits or {}, candidate_count or #rows, {}, HARD_BLOCKERS)
end

local function candidates_for_rule(rule, indexes, seeds)
  return provider_discovery.candidates(rule, indexes, seeds)
end

local function rows_by_provider(decisions)
  local result = {}
  for _, row in ipairs(decisions or {}) do
    local rows = result[row.provider_id]
    if not rows then
      rows = {}
      result[row.provider_id] = rows
    end
    table.insert(rows, row)
  end
  return result
end

local function rule_for_provider(provider_id)
  local selected = nil
  for _, rule in ipairs(rule_registry.view().rules or {}) do
    -- Preserve the former rules_by_provider assignment semantics: the last
    -- validated rule wins when diagnostic rules share a provider id.
    if rule.provider_id == provider_id then selected = rule end
  end
  return selected
end

-- Provider metrics are diagnostic evidence, not an input to provider
-- selection, ownership, emission, or the pure compilation snapshot. Preserve
-- only the Context-owned pre-emission anchors needed to construct them on
-- demand.
local function metric_inputs_for(resolution)
  local context = compiler_context.current()
  local inputs = context:state_view("provider_metric_inspection_inputs")
  if type(inputs) ~= "table" or inputs.schema ~= 1
    or type(inputs.phase_seconds) ~= "table"
    or type(inputs.metric_rows_by_provider) ~= "table"
    or type(inputs.recipe_unlock_source_epoch) ~= "number"
    or type(inputs.environment_fingerprint) ~= "string" then
    error("Provider metric inspection inputs are missing from the active family resolution.", 3)
  end
  if type(inputs.environment_identity) ~= "table"
    or inputs.environment_identity.environment_fingerprint ~= inputs.environment_fingerprint
    or resolution.environment_fingerprint ~= inputs.environment_fingerprint then
    error("Provider metric inspection environment does not match the resolved provider decisions.", 3)
  end
  environment_identity.assert_trusted(inputs.environment_identity)
  if recipe_facts.source_epoch() ~= inputs.recipe_unlock_source_epoch then
    error("Provider metric inspection recipe source epoch differs from the resolved provider decisions.", 3)
  end
  -- `build()` populated this Context-owned index while it evaluated each
  -- candidate before emission. Do not rebuild it from post-emission data.raw.
  if #(resolution.decisions or {}) > 0 then
    local unlock_index = context:state_view("recipe_unlock_index")
    if type(unlock_index) ~= "table"
      or unlock_index.recipe_source_epoch ~= inputs.recipe_unlock_source_epoch then
      error("Provider metric inspection pre-emission recipe unlock index is unavailable.", 3)
    end
  end
  local researchability = context:state_view("technology_researchability_index")
  if type(researchability) ~= "table" then
    error("Provider metric inspection pre-emission researchability index is unavailable.", 3)
  end
  return inputs, researchability
end

local function build_provider_metrics(resolution, provider_id)
  local rule = rule_for_provider(provider_id)
  if not rule then return nil end
  local inputs, researchability = metric_inputs_for(resolution)
  return provider_metrics.build(
    rule,
    inputs.metric_rows_by_provider[provider_id] or {},
    resolution.provider_cardinality[provider_id],
    {
      researchability_index = researchability,
      environment_identity = inputs.environment_identity,
      environment_fingerprint = inputs.environment_fingerprint,
      phase_seconds = inputs.phase_seconds[provider_id]
    }
  )
end

local function build()
  local context = compiler_context.current()
  local canonical = context:state_view("family_resolution")
  if canonical then return canonical end
  local indexes = relationships.view()
  local rules = rule_registry.view().rules
  local seeds = policy_authority.candidate_seeds()
  local attachments, decisions, provider_cardinality = {}, {}, {}
  local attachment_claims, phase_seconds = {}, {}
  local researchability = context:state_view("technology_researchability_index", researchability_index.build)
  local environment = environment_adapter.current()
  telemetry.start_phase("provider_discovery")

  for _, seed in ipairs(seeds) do
    local matched = false
    for _, rule in ipairs(rules) do
      if seed.family == rule.id and seed.stream == operator_dsl.grouping_stream(rule.operators) then matched = true; break end
    end
    if not matched then
      error("CompatibilityPack candidate seed references unknown family/stream: " .. seed.family .. "/" .. seed.stream, 2)
    end
  end

  for _, rule in ipairs(rules) do
    local clock_available = os and type(os.clock) == "function"
    local phase_started = clock_available and os.clock() or nil
    local target_stream = operator_dsl.grouping_stream(rule.operators)
    local candidates = candidates_for_rule(rule, indexes, seeds)
    local rule_decisions = {}
    telemetry.count("provider_candidates", #candidates)
    for _, raw_candidate in ipairs(candidates) do
      local candidate = provider_normalization.candidate(raw_candidate, rule)
      local classified = provider_classification.evaluate(rule, candidate)
      local pack_decision = provider_pack_policy.resolve(rule, target_stream, candidate, classified.blocker)
      local resolved = provider_hazard_policy.resolve(
        classified, pack_decision, HARD_BLOCKERS, policy_authority.blocker_is_reviewable)
      if classified.ambiguity then
        resolved = {eligible = false, blocker = classified.blocker, risk_disposition = "REVIEW_REQUIRED"}
      end
      classified.eligible = resolved.eligible
      classified.blocker = resolved.blocker
      classified.risk_disposition = resolved.risk_disposition
      local owner_blocker = provider_owner_arbitration.blocker(candidate.recipe)
      if owner_blocker then classified.eligible, classified.blocker = false, owner_blocker end

      local change = operator_dsl.effect_change(rule.operators, candidate, indexes)
      if tonumber(pack_decision.change) then change = tonumber(pack_decision.change) end
      local action = operator_dsl.grouping_action(rule.operators)
      if not classified.eligible then
        action = classified.risk_disposition == "REVIEW_REQUIRED" and "review-required" or "diagnose"
      end
      local earliest_depth
      for _, unlocker in ipairs(recipe_unlocks.for_recipe(candidate.recipe)) do
        local depth = researchability.unlock_depths[unlocker]
        if type(depth) == "number" then earliest_depth = earliest_depth and math.min(earliest_depth, depth) or depth end
      end
      local decision_row = provider_decision.build(
        rule, target_stream, candidate, classified, pack_decision, change, action, earliest_depth)
      table.insert(rule_decisions, decision_row)
    end

    local cardinality = provider_budget.apply(rule_decisions, rule.cardinality, #candidates, {
      provider_id = rule.provider_id,
      family = rule.id,
      partition = "single",
      profile = "active-target"
    }, HARD_BLOCKERS)
    provider_cardinality[rule.provider_id] = cardinality
    if cardinality.status == "REVIEW_REQUIRED" then telemetry.count("provider_cardinality_review_required", 1) end
    for _, decision_row in ipairs(rule_decisions) do
      table.insert(decisions, decision_row)
      if decision_row.final_state == "review-required" then telemetry.count("provider_review_required", 1) end
      if decision_row.final_state == "attach" then
        attachment_claims[decision_row.recipe] = attachment_claims[decision_row.recipe] or {}
        table.insert(attachment_claims[decision_row.recipe], decision_row)
      end
    end
    phase_seconds[rule.provider_id] = phase_started and math.max(0, os.clock() - phase_started) or nil
  end

  local claimed_recipes = {}
  for recipe_name in pairs(attachment_claims) do table.insert(claimed_recipes, recipe_name) end
  table.sort(claimed_recipes)
  for _, recipe_name in ipairs(claimed_recipes) do
    local claims = attachment_claims[recipe_name]
    local arbitration = provider_claim.arbitrate(claims)
    if arbitration.status ~= "PASS" then
      local streams = {}
      for _, claim in ipairs(claims) do streams[claim.target_stream] = true end
      local stream_names = {}
      for stream_name in pairs(streams) do table.insert(stream_names, stream_name) end
      table.sort(stream_names)
      for _, claim in ipairs(claims) do
        claim.final_state = "review-required"
        claim.decision = "review-required"
        claim.blocker = arbitration.code
        claim.risk_disposition = "REVIEW_REQUIRED"
        claim.ambiguity = {code = arbitration.code, candidate_streams = deepcopy(stream_names)}
        provider_decision.refresh_fingerprint(claim)
        telemetry.count("provider_review_required", 1)
      end
    else
      local attachment = arbitration.attachment
      attachments[attachment.target_stream] = attachments[attachment.target_stream] or {}
      table.insert(attachments[attachment.target_stream], attachment)
    end
  end

  -- ProviderMetrics historically received the decision order before the
  -- public deterministic sort below. Its witness truncation and canonical
  -- byte measurement are sequence-sensitive, so retain references only in
  -- the Context-owned inspection anchor; do not copy this diagnostic input.
  local metric_rows_by_provider = rows_by_provider(decisions)

  for _, rows in pairs(attachments) do
    table.sort(rows, function(a, b)
      if a.change ~= b.change then return a.change > b.change end
      return a.recipe < b.recipe
    end)
  end
  table.sort(decisions, function(a, b)
    if a.rule ~= b.rule then return a.rule < b.rule end
    if a.recipe ~= b.recipe then return a.recipe < b.recipe end
    return tostring(a.item) < tostring(b.item)
  end)
  telemetry.count("family_members", (function()
    local count = 0
    for _, rows in pairs(attachments) do count = count + #rows end
    return count
  end)())
  telemetry.finish_phase("provider_discovery")
  environment_identity.assert_trusted(environment)
  canonical = {
    schema = 3,
    attachments = attachments,
    decisions = decisions,
    provider_cardinality = provider_cardinality,
    environment_fingerprint = environment.environment_fingerprint,
    decision_set_fingerprint = fingerprint.of(decisions)
  }
  context:set_state("provider_metric_inspection_inputs", {
    schema = 1,
    environment_identity = environment,
    environment_fingerprint = environment.environment_fingerprint,
    recipe_unlock_source_epoch = recipe_facts.source_epoch(),
    phase_seconds = phase_seconds,
    metric_rows_by_provider = metric_rows_by_provider
  })
  return context:set_state("family_resolution", canonical)
end

local function query_index()
  local context = compiler_context.current()
  local cached = context:state_view("family_resolution_query_index")
  if cached then return cached end
  local resolution = build()
  local streams = {}
  local function stream(key)
    local row = streams[key]
    if row then return row end
    row = {
      provider_ids = {},
      family_ids = {},
      decisions = {},
      decision_fingerprints = {},
      risk_fingerprints = {}
    }
    streams[key] = row
    return row
  end

  for stream_key, attachments in pairs(resolution.attachments or {}) do
    local row, seen = stream(stream_key), {}
    for _, attachment in ipairs(attachments) do
      if not seen[attachment.provider_id] then
        seen[attachment.provider_id] = true
        row.provider_ids[#row.provider_ids + 1] = attachment.provider_id
      end
    end
  end
  for _, decision in ipairs(resolution.decisions or {}) do
    local row = stream(decision.target_stream)
    row.decisions[#row.decisions + 1] = decision
    row.decision_fingerprints[#row.decision_fingerprints + 1] = decision.decision_fingerprint
    row._family_seen = row._family_seen or {}
    if decision.candidate_family and not row._family_seen[decision.candidate_family] then
      row._family_seen[decision.candidate_family] = true
      row.family_ids[#row.family_ids + 1] = decision.candidate_family
    end
    row._risk_seen = row._risk_seen or {}
    if not row._risk_seen[decision.risk_fingerprint] then
      row._risk_seen[decision.risk_fingerprint] = true
      row.risk_fingerprints[#row.risk_fingerprints + 1] = decision.risk_fingerprint
    end
  end
  for _, row in pairs(streams) do
    table.sort(row.provider_ids)
    table.sort(row.family_ids)
    table.sort(row.decision_fingerprints)
    table.sort(row.risk_fingerprints)
    row._family_seen = nil
    row._risk_seen = nil
  end
  return context:set_state("family_resolution_query_index", {
    schema = 1,
    streams = streams
  })
end

local function scalar_array(values)
  local out = {}
  for index, value in ipairs(values or {}) do out[index] = value end
  return out
end

function M.attachments_for_stream(stream_key)
  return deepcopy(build().attachments[stream_key] or {})
end

function M.provider_ids_for_stream(stream_key)
  local row = query_index().streams[stream_key]
  return scalar_array(row and row.provider_ids)
end

function M.family_ids_for_stream(stream_key)
  local row = query_index().streams[stream_key]
  return scalar_array(row and row.family_ids)
end

function M.decisions_for_stream(stream_key)
  local row = query_index().streams[stream_key]
  return deepcopy((row and row.decisions) or {})
end

function M.decision_fingerprints_for_stream(stream_key)
  local row = query_index().streams[stream_key]
  return scalar_array(row and row.decision_fingerprints)
end

function M.risk_fingerprints_for_stream(stream_key)
  local row = query_index().streams[stream_key]
  return scalar_array(row and row.risk_fingerprints)
end

function M.decision_set_fingerprint()
  return build().decision_set_fingerprint
end

function M.apply_cardinality_guard(rows, limits, candidate_count)
  local copy = deepcopy(rows or {})
  return copy, apply_cardinality_guard(copy, limits or {}, candidate_count or #copy)
end

function M.snapshot()
  return deepcopy(build())
end

function M.view()
  return build()
end

-- The compiler input needs the exact decision rows, not diagnostic metric
-- inventory, cardinality evidence, attachments, or Context-only anchors.
-- Keep the full rows (rather than only their digest): pure compiler and plan
-- builders consume their semantic fields after snapshot qualification.
function M.compilation_projection()
  local resolution = build()
  return {
    schema = 1,
    decisions = resolution.decisions,
    decision_set_fingerprint = resolution.decision_set_fingerprint
  }
end

function M.metrics_for_provider(provider_id)
  return deepcopy(build_provider_metrics(build(), provider_id))
end

-- Existing internal evidence requests a complete resolver inspection only
-- when diagnostics/include_internal is enabled. Normal player startup never
-- constructs ProviderMetrics or emits a synthetic empty substitute.
function M.inspection_snapshot()
  local resolution = build()
  local inspection = deepcopy(resolution)
  inspection.provider_metrics = {}
  local inspected = {}
  for _, rule in ipairs(rule_registry.view().rules or {}) do
    if not inspected[rule.provider_id] then
      inspected[rule.provider_id] = true
      local metrics = build_provider_metrics(resolution, rule.provider_id)
      if metrics then inspection.provider_metrics[rule.provider_id] = metrics end
    end
  end
  return inspection
end

return M
