local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1
local DECISIONS = {approved = true, quarantined = true, demoted = true}

local function material(record)
  return {
    schema = record.schema,
    approval_id = record.approval_id,
    decision = record.decision,
    candidate_selector = record.candidate_selector,
    applicability = record.applicability,
    selected_alternative = record.selected_alternative,
    approved_design_fingerprint = record.approved_design_fingerprint,
    qualification_fingerprint = record.qualification_fingerprint,
    locked_fields = record.locked_fields,
    adaptive_envelopes = record.adaptive_envelopes,
    required_evidence = record.required_evidence,
    reviewer = record.reviewer,
    decided_at = record.decided_at,
    reason = record.reason
  }
end

local function validate_strings(values, label)
  if type(values) ~= "table" then error("TechnologyApproval " .. label .. " must be a list.", 3) end
  for _, value in ipairs(values) do
    if type(value) ~= "string" or value == "" then
      error("TechnologyApproval " .. label .. " contains an invalid value.", 3)
    end
  end
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    decisions = {"approved", "quarantined", "demoted"},
    required = {
      "approval_id", "decision", "candidate_selector", "applicability", "locked_fields",
      "adaptive_envelopes", "required_evidence", "reviewer", "decided_at", "approval_fingerprint"
    }
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyApproval schema 1 record is required.", 2)
  end
  for _, field in ipairs({"approval_id", "reviewer", "decided_at"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyApproval field is required: " .. field, 2)
    end
  end
  if not DECISIONS[record.decision] or type(record.candidate_selector) ~= "table"
    or type(record.applicability) ~= "table" or type(record.adaptive_envelopes) ~= "table" then
    error("TechnologyApproval decision material is invalid.", 2)
  end
  if type(record.candidate_selector.candidate_id) ~= "string"
    and type(record.candidate_selector.semantic_identity) ~= "table" then
    error("TechnologyApproval candidate selector is invalid.", 2)
  end
  validate_strings(record.locked_fields, "locked_fields")
  validate_strings(record.required_evidence, "required_evidence")
  if record.decision == "approved" then
    if type(record.selected_alternative) ~= "string" or record.selected_alternative == ""
      or type(record.approved_design_fingerprint) ~= "string" or record.approved_design_fingerprint == ""
      or type(record.qualification_fingerprint) ~= "string" or record.qualification_fingerprint == "" then
      error("Approved TechnologyApproval requires an exact alternative, design, and qualification.", 2)
    end
  elseif type(record.reason) ~= "string" or record.reason == "" then
    error("Quarantined or demoted TechnologyApproval requires a reason.", 2)
  end
  if record.approval_fingerprint ~= fingerprint.of(material(record)) then
    error("TechnologyApproval fingerprint is invalid.", 2)
  end
  return true
end

function M.new(record)
  local out = deepcopy(record or {})
  out.schema = SCHEMA
  out.locked_fields = deepcopy(out.locked_fields or {})
  out.adaptive_envelopes = deepcopy(out.adaptive_envelopes or {})
  out.required_evidence = deepcopy(out.required_evidence or {})
  out.approval_fingerprint = fingerprint.of(material(out))
  M.validate(out)
  return out
end

return M
