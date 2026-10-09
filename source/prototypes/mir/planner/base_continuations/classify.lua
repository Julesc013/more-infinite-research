local fingerprint = require("prototypes.mir.core.fingerprint")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")

local M = {}

local function base_gate_vector(key, reason, failed_gate)
  local input_fingerprint = fingerprint.of({key = key, reason = reason})
  local gates = {}
  for _, gate_name in ipairs(hard_gate_authority.order()) do
    gates[gate_name] = gate_contract.not_applicable(
      "base-continuation-planner",
      "base-continuation-materializes",
      fingerprint.of({input_fingerprint = input_fingerprint, gate = gate_name}),
      {"base-continuation:not-materialized:" .. tostring(reason)}
    )
  end
  if failed_gate then
    gates[failed_gate] = gate_contract.failed(
      "base-continuation-planner", tostring(reason), {"base-continuation:" .. tostring(reason)})
  end
  return gates
end

function M.rejected_candidate(key, reason, failed_gate)
  return nil, {
    schema = 1,
    candidate_id = "base-continuation/" .. tostring(key),
    key = key,
    action = "reject",
    reason = reason,
    gates = base_gate_vector(key, reason, failed_gate),
    candidate_fingerprint = fingerprint.of({key = key, reason = reason, failed_gate = failed_gate})
  }
end

function M.accepted_gate_vector(key, technology_name)
  local input_fingerprint = fingerprint.of({key = key, technology_name = technology_name})
  local passed = function(evaluator, evidence) return gate_contract.passed(evaluator, {evidence}) end
  return {
    target_supported = passed("target-profile", "base-continuation:target-supported"),
    effect_valid = gate_contract.pending("effect-contracts"),
    owner_conflict_free = passed("base-continuation-planner", "base-continuation:owner-free"),
    science_compatible = passed("science-selector", "base-continuation:science-resolved"),
    lab_compatible = passed("lab-compatibility", "base-continuation:lab-resolved"),
    prerequisites_acyclic = gate_contract.pending("technology-graph"),
    loop_safe = gate_contract.not_applicable(
      "base-continuation-planner", "candidate-transforms-recipe-graph", input_fingerprint,
      {"base-continuation:no-recipe-graph-transformation"}),
    progression_safe = gate_contract.pending("technology-graph"),
    migration_safe = passed("base-continuation-manifest", "base-continuation:stable-chain"),
    output_identity_safe = passed("base-continuation-planner", "base-continuation:output-absent")
  }
end

return M
