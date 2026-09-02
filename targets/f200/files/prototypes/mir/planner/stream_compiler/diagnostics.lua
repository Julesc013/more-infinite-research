local D = require("prototypes.mir.report.diagnostics_sink")
local family_resolver = require("prototypes.mir.families.resolver")
local fingerprint = require("prototypes.mir.core.fingerprint")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local technology_risk = require("prototypes.mir.domain.technology.technology_risk")

local M = {}
local shared_materializing_gates = {}
local shared_skip_gates = {}

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

local function shared_default_gate(action, gate_name, contract)
  local cache = action == "skip" and shared_skip_gates or shared_materializing_gates
  if cache[gate_name] then return cache[gate_name] end
  if action == "skip" then
    cache[gate_name] = gate_contract.not_applicable(
      "generation-plan",
      "candidate-action-is-materializing",
      fingerprint.of({action = action, gate = gate_name}),
      {"decision:non-materializing-row"}
    )
  elseif contract.initial == "pending" then
    cache[gate_name] = gate_contract.pending(contract.evaluator)
  else
    cache[gate_name] = gate_contract.passed(contract.evaluator, {contract.evidence})
  end
  return cache[gate_name]
end

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
    else
      out[gate_name] = shared_default_gate(action, gate_name, contract)
    end
  end
  return out
end

function M.localized_name(key, spec)
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

function M.localized_description(spec)
  local description
  if spec.localised_description then
    description = spec.localised_description
  elseif spec.description_locale_key then
    description = { spec.description_locale_key }
  elseif spec.direct_effects then
    description = {"technology-description.more-infinite-research.direct_effect"}
  else
    description = {"technology-description.more-infinite-research.recipe_productivity"}
  end
  return technology_risk.append_tooltip(description, spec.technology_risk)
end

function M.plan_row(key, spec, action, reason, diagnostics, extra)
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
    technology_risk = technology_risk.classification(spec.technology_risk),
    spec = spec,
    diagnostics = diagnostics,
    gates = proof_gates(action, extra.failed_gates)
  }
  for field, value in pairs(extra) do
    if field ~= "failed_gates" then row[field] = value end
  end
  return row
end

function M.skip_row(key, spec, reason, ingredients, effects, lab_status, extra, failed_gates)
  local diagnostics_extra = extra
  extra = extra or {}
  extra.failed_gates = failed_gates
  return M.plan_row(
    key,
    spec,
    "skip",
    reason,
    D.stream_fields(key, spec, "skipped", reason, ingredients, nil, effects, lab_status, diagnostics_extra),
    extra
  )
end

return M
