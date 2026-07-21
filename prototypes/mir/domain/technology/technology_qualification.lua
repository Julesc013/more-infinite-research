local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local technology_design = require("prototypes.mir.domain.technology.technology_design")

local M = {}
local SCHEMA = 1
local GATE_ORDER = {
  "target_supported", "effect_valid", "owner_conflict_free", "science_compatible", "lab_compatible",
  "prerequisites_acyclic", "loop_safe", "progression_safe", "migration_safe", "output_identity_safe"
}
local DECISIONS = {qualified = true, proposal = true, rejected = true, quarantined = true}

local function qualification_material(record)
  return {
    schema = record.schema,
    candidate_id = record.candidate_id,
    design_fingerprint = record.design_fingerprint,
    context_fingerprint = record.context_fingerprint,
    hard_gates = record.hard_gates,
    quality_metrics = record.quality_metrics,
    decision = record.decision,
    primary_rejection = record.primary_rejection,
    contributing_rejections = record.contributing_rejections,
    validation_evidence = record.validation_evidence
  }
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    gate_order = deepcopy(GATE_ORDER),
    decisions = {"qualified", "proposal", "rejected", "quarantined"},
    required = {
      "candidate_id", "design_fingerprint", "context_fingerprint", "hard_gates", "quality_metrics",
      "decision", "contributing_rejections", "validation_evidence", "qualification_fingerprint"
    }
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyQualification schema 1 record is required.", 2)
  end
  for _, field in ipairs({"candidate_id", "design_fingerprint", "context_fingerprint", "validation_evidence"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyQualification field is required: " .. field, 2)
    end
  end
  if type(record.hard_gates) ~= "table" or type(record.quality_metrics) ~= "table"
    or type(record.contributing_rejections) ~= "table" or not DECISIONS[record.decision] then
    error("TechnologyQualification decision material is invalid.", 2)
  end
  if record.primary_rejection ~= nil and type(record.primary_rejection) ~= "table" then
    error("TechnologyQualification primary rejection is invalid.", 2)
  end
  if record.qualification_fingerprint ~= fingerprint.of(qualification_material(record)) then
    error("TechnologyQualification fingerprint is invalid.", 2)
  end
  return true
end

function M.from_design(design, row, quality_metrics, options)
  if not (options and options.validated) then technology_design.validate(design) end
  row = row or {}
  local contributing = {}
  for _, gate_name in ipairs(GATE_ORDER) do
    local gate = row.gates and row.gates[gate_name]
    if gate and gate.status == "failed" then
      table.insert(contributing, {
        gate = gate_name,
        reason = gate.reason,
        evidence = deepcopy(gate.evidence or {})
      })
    end
  end
  local primary = contributing[1]
  if not primary and row.action == "skip" and row.reason then
    primary = {gate = "materialization", reason = row.reason, evidence = {"generation-plan:" .. row.reason}}
  end
  local decision = primary and "rejected" or
    ((row.action == "emit" or row.action == "adopt") and "qualified" or "proposal")
  local record = {
    schema = SCHEMA,
    candidate_id = design.candidate_id,
    design_fingerprint = design.design_fingerprint,
    context_fingerprint = fingerprint.of(design.context),
    hard_gates = deepcopy(row.gates or {}),
    quality_metrics = deepcopy(quality_metrics or {status = "unmeasured"}),
    decision = decision,
    primary_rejection = deepcopy(primary),
    contributing_rejections = contributing,
    validation_evidence = design.maturity.validation_evidence
  }
  record.qualification_fingerprint = fingerprint.of(qualification_material(record))
  M.validate(record)
  return record
end

return M
