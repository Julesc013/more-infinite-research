local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}
local SCHEMA = 1
local GATE_ORDER = {
  "target_supported", "effect_valid", "owner_conflict_free", "science_compatible", "lab_compatible",
  "prerequisites_acyclic", "loop_safe", "progression_safe", "migration_safe", "output_identity_safe"
}
local DECISIONS = {qualified = true, proposal = true, rejected = true, quarantined = true}

local function material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    candidate_id = record.candidate_id,
    design_fingerprint = record.design_fingerprint,
    context_fingerprint = record.context_fingerprint,
    hard_gates = record.hard_gates,
    decision = record.decision,
    unresolved_gates = record.unresolved_gates,
    primary_rejection = record.primary_rejection,
    contributing_rejections = record.contributing_rejections,
    validation_evidence = record.validation_evidence
  }
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    record_type = "SafetyQualification",
    gate_order = deepcopy(GATE_ORDER),
    decisions = {"qualified", "proposal", "rejected", "quarantined"}
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "SafetyQualification" then
    error("SafetyQualification schema 1 record is required.", 2)
  end
  for _, field in ipairs({"candidate_id", "design_fingerprint", "context_fingerprint", "validation_evidence"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("SafetyQualification field is required: " .. field, 2)
    end
  end
  if type(record.hard_gates) ~= "table" or type(record.contributing_rejections) ~= "table"
    or type(record.unresolved_gates) ~= "table"
    or not DECISIONS[record.decision] then
    error("SafetyQualification decision material is invalid.", 2)
  end
  for _, gate in pairs(record.hard_gates) do gate_contract.validate(gate) end
  if record.primary_rejection ~= nil and type(record.primary_rejection) ~= "table" then
    error("SafetyQualification primary rejection is invalid.", 2)
  end
  if record.qualification_fingerprint ~= fingerprint.of(material(record)) then
    error("SafetyQualification fingerprint is invalid.", 2)
  end
  return true
end

function M.from_design(design, row, _, options)
  if not (options and options.validated) then technology_design.validate(design) end
  row = row or {}
  local contributing = {}
  local unresolved = {}
  local hard_gates = {}
  for _, gate_name in ipairs(GATE_ORDER) do
    local gate = row.gates and row.gates[gate_name] or gate_contract.not_applicable(
      "safety-qualification:total-gate-vector",
      {"safety-qualification:not-applicable:" .. gate_name}
    )
    gate_contract.validate(gate)
    hard_gates[gate_name] = deepcopy(gate)
    if gate.status == "failed" then
      table.insert(contributing, {gate = gate_name, reason = gate.reason, evidence = deepcopy(gate.evidence)})
    elseif gate.status == "pending" or gate.status == "superseded" then
      table.insert(unresolved, gate_name)
    end
  end
  local primary = contributing[1]
  local materializing = row.action == "emit" or row.action == "adopt"
  if not primary and row.action == "skip" and row.reason then
    primary = {gate = "materialization", reason = row.reason, evidence = {"generation-plan:" .. row.reason}}
  end
  local decision = primary and "rejected" or
    (materializing and #unresolved > 0) and "proposal" or
    ((materializing or row.action == "diagnose") and "qualified" or "proposal")
  local record = {
    schema = SCHEMA,
    record_type = "SafetyQualification",
    candidate_id = design.candidate_id,
    design_fingerprint = design.design_fingerprint,
    context_fingerprint = fingerprint.of(design.context),
    hard_gates = hard_gates,
    decision = decision,
    unresolved_gates = deepcopy(unresolved),
    primary_rejection = deepcopy(primary),
    contributing_rejections = contributing,
    validation_evidence = design.maturity.validation_evidence
  }
  record.qualification_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

return M
