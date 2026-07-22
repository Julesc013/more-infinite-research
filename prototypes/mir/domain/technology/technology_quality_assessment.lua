local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1
local STATUSES = {UNMEASURED = true, REVIEW_REQUIRED = true, PASS = true, FAIL = true}
local REQUIRED_NUMBERS = {
  "member_count", "semantic_cluster_count", "earliest_unlock_depth", "latest_unlock_depth",
  "progression_span", "science_tier_span", "accepting_lab_count", "owner_conflict_count",
  "effect_per_level", "cost_l1", "cost_l5", "cost_l10", "cost_l20",
  "useful_levels_before_cap", "true_positive_count", "false_positive_count", "false_negative_count",
  "cross_version_add_count", "cross_version_remove_count", "provider_phase_time"
}

local function material(record)
  local out = {}
  for key, value in pairs(record) do
    if key ~= "assessment_fingerprint" then out[key] = value end
  end
  return out
end

function M.schema_authority()
  return {
    schema = SCHEMA,
    statuses = {"UNMEASURED", "REVIEW_REQUIRED", "PASS", "FAIL"},
    required_numbers = deepcopy(REQUIRED_NUMBERS)
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyQualityAssessment schema 1 record is required.", 2)
  end
  for _, field in ipairs({"candidate_id", "design_fingerprint", "qualification_fingerprint", "profile_id"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyQualityAssessment field is required: " .. field, 2)
    end
  end
  for _, field in ipairs(REQUIRED_NUMBERS) do
    if type(record[field]) ~= "number" or record[field] < 0 then
      error("TechnologyQualityAssessment metric is invalid: " .. field, 2)
    end
  end
  if not STATUSES[record.status] or type(record.review_reasons) ~= "table"
    or type(record.evidence_sha256) ~= "table" then
    error("TechnologyQualityAssessment decision material is invalid.", 2)
  end
  if record.assessment_fingerprint ~= fingerprint.of(material(record)) then
    error("TechnologyQualityAssessment fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  values = deepcopy(values or {})
  values.schema = SCHEMA
  values.review_reasons = values.review_reasons or {}
  values.evidence_sha256 = values.evidence_sha256 or {}
  for _, field in ipairs(REQUIRED_NUMBERS) do values[field] = tonumber(values[field]) or 0 end
  values.status = values.status or "UNMEASURED"
  values.assessment_fingerprint = fingerprint.of(material(values))
  M.validate(values)
  return values
end

return M
