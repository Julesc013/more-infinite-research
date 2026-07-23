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
local provider_budget = require("prototypes.mir.providers.pipeline.budget")

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
  non_deterministic_placeable_output = true,
  existing_recipe_productivity_owner = true
}

local function apply_cardinality_guard(rows, limits, candidate_count)
  return provider_budget.apply(rows, limits or {}, candidate_count or #rows, {}, HARD_BLOCKERS)
end

local function candidates_for_rule(rule, indexes, seeds)
  return provider_discovery.candidates(rule, indexes, seeds)
end

local function build()
  local context = compiler_context.current()
  local canonical = context:state_view("family_resolution")
  if canonical then return canonical end
  local indexes = relationships.view()
  local rules = rule_registry.snapshot().rules
  local seeds = policy_authority.candidate_seeds()
  local attachments, decisions, ownership, provider_cardinality = {}, {}, {}, {}
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
      table.insert(rule_decisions, provider_decision.build(
        rule, target_stream, candidate, classified, pack_decision, change, action))
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
          local recipe_name = decision_row.recipe
          local target_stream = decision_row.target_stream
          local previous = ownership[recipe_name]
          if previous and previous ~= target_stream then
            error("FamilyRule attachment is ambiguous for recipe " .. recipe_name, 2)
          end
          ownership[recipe_name] = target_stream
          attachments[target_stream] = attachments[target_stream] or {}
          table.insert(attachments[target_stream], {
            recipe = recipe_name,
            change = decision_row.change,
            rule = rule.id,
            provider_id = rule.provider_id,
            risk_fingerprint = decision_row.risk_fingerprint,
            decision_fingerprint = decision_row.decision_fingerprint
          })
        end
    end
  end

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
  canonical = {
    schema = 3,
    attachments = attachments,
    decisions = decisions,
    provider_cardinality = provider_cardinality,
    decision_set_fingerprint = fingerprint.of(decisions)
  }
  return context:set_state("family_resolution", canonical)
end

function M.attachments_for_stream(stream_key)
  return deepcopy(build().attachments[stream_key] or {})
end

function M.provider_ids_for_stream(stream_key)
  local ids, seen = {}, {}
  for _, attachment in ipairs(build().attachments[stream_key] or {}) do
    if not seen[attachment.provider_id] then
      seen[attachment.provider_id] = true
      table.insert(ids, attachment.provider_id)
    end
  end
  table.sort(ids)
  return ids
end

function M.family_ids_for_stream(stream_key)
  local ids, seen = {}, {}
  for _, decision in ipairs(build().decisions or {}) do
    if decision.target_stream == stream_key and decision.candidate_family
      and not seen[decision.candidate_family] then
      seen[decision.candidate_family] = true
      table.insert(ids, decision.candidate_family)
    end
  end
  table.sort(ids)
  return ids
end

function M.decisions_for_stream(stream_key)
  local out = {}
  for _, decision in ipairs(build().decisions or {}) do
    if decision.target_stream == stream_key then table.insert(out, deepcopy(decision)) end
  end
  return out
end

function M.decision_fingerprints_for_stream(stream_key)
  local out = {}
  for _, decision in ipairs(build().decisions or {}) do
    if decision.target_stream == stream_key then table.insert(out, decision.decision_fingerprint) end
  end
  table.sort(out)
  return out
end

function M.risk_fingerprints_for_stream(stream_key)
  local seen, out = {}, {}
  for _, decision in ipairs(build().decisions or {}) do
    if decision.target_stream == stream_key and not seen[decision.risk_fingerprint] then
      seen[decision.risk_fingerprint] = true
      table.insert(out, decision.risk_fingerprint)
    end
  end
  table.sort(out)
  return out
end

function M.apply_cardinality_guard(rows, limits, candidate_count)
  local copy = deepcopy(rows or {})
  return copy, apply_cardinality_guard(copy, limits or {}, candidate_count or #copy)
end

function M.snapshot()
  return deepcopy(build())
end

return M
