local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local technology_design = require("prototypes.mir.domain.technology.technology_design")
local hard_gate_authority = require("prototypes.mir.domain.technology.hard_gate_authority")

local M = {}
local authority = trusted_record.new("SafetyQualification")
local SCHEMA = 1
local GATE_ORDER = hard_gate_authority.order()
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

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    candidate_id = record.candidate_id,
    design_fingerprint = record.design_fingerprint,
    qualification_fingerprint = record.qualification_fingerprint,
    decision = record.decision
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.candidate_id == registered.candidate_id
    and record.design_fingerprint == registered.design_fingerprint
    and record.qualification_fingerprint == registered.qualification_fingerprint
    and record.decision == registered.decision
end

local function verify(record, options)
  options = options or {}
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
  hard_gate_authority.assert_total(record.hard_gates)
  for _, gate in pairs(record.hard_gates) do
    if options.trusted_children then gate_contract.assert_trusted(gate) else gate_contract.verify_untrusted(gate) end
  end
  if record.primary_rejection ~= nil and type(record.primary_rejection) ~= "table" then
    error("SafetyQualification primary rejection is invalid.", 2)
  end
  if record.qualification_fingerprint ~= fingerprint.of(material(record)) then
    error("SafetyQualification fingerprint is invalid.", 2)
  end
  return true
end


function M.verify_untrusted(record)
  authority.verify_untrusted(record, verify, trust_identity(record or {}))
  return true
end


function M.validate(record)
  return M.verify_untrusted(record)
end


function M.assert_trusted(record)
  return authority.assert_trusted(record, trust_identity_unchanged)
end


function M.is_trusted(record)
  return authority.is_trusted(record)
end

function M.from_design(design, row, _, options)
  if options and options.validated then technology_design.assert_trusted(design)
  else technology_design.verify_untrusted(design) end
  row = row or {}
  local contributing = {}
  local unresolved = {}
  local hard_gates = {}
  for _, gate_name in ipairs(GATE_ORDER) do
    local gate = row.gates and row.gates[gate_name]
    if gate == nil then
      error("SafetyQualification candidate is missing required hard gate: " .. gate_name, 2)
    end
    if gate_contract.is_trusted(gate) then gate_contract.assert_trusted(gate)
    else gate_contract.verify_untrusted(gate) end
    hard_gates[gate_name] = gate
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
  verify(record, {trusted_children = true})
  return authority.register(record, trust_identity(record))
end

return M
