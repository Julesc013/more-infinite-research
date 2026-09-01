local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 2
local STATUSES = {REVIEW_REQUIRED = true, PASS = true, FAIL = true}
local MEASUREMENT_STATUSES = {COMPLETE = true, INCOMPLETE = true}
local STATUS_SEVERITY = {PASS = 0, REVIEW_REQUIRED = 1, FAIL = 2}
local REQUIRED_NUMBERS = {
  "member_count", "semantic_cluster_count", "earliest_unlock_depth", "latest_unlock_depth",
  "progression_span", "science_tier_span", "accepting_lab_count", "owner_conflict_count",
  "effect_per_level", "cost_l1", "cost_l5", "cost_l10", "cost_l20",
  "useful_levels_before_cap", "true_positive_count", "false_positive_count", "false_negative_count",
  "cross_version_add_count", "cross_version_remove_count", "provider_phase_time",
  "provider_canonical_bytes", "provider_witness_count"
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
    statuses = {"REVIEW_REQUIRED", "PASS", "FAIL"},
    measurement_statuses = {"COMPLETE", "INCOMPLETE"},
    required_numbers = deepcopy(REQUIRED_NUMBERS)
  }
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA then
    error("TechnologyQualityAssessment schema 2 record is required.", 2)
  end
  for _, field in ipairs({"candidate_id", "design_fingerprint", "qualification_fingerprint", "profile_id"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TechnologyQualityAssessment field is required: " .. field, 2)
    end
  end
  if not MEASUREMENT_STATUSES[record.measurement_status]
    or type(record.metric_provenance) ~= "table" or type(record.thresholds) ~= "table" then
    error("TechnologyQualityAssessment measurement authority is invalid.", 2)
  end
  for _, field in ipairs(REQUIRED_NUMBERS) do
    if record.measurement_status == "COMPLETE" and (type(record[field]) ~= "number" or record[field] < 0) then
      error("TechnologyQualityAssessment metric is invalid: " .. field, 2)
    end
    if record[field] ~= nil and (type(record[field]) ~= "number" or record[field] < 0) then
      error("TechnologyQualityAssessment measured metric is invalid: " .. field, 2)
    end
    local provenance = record.metric_provenance[field]
    if type(provenance) ~= "table" or not MEASUREMENT_STATUSES[provenance.measurement_status]
      or type(provenance.source) ~= "string" or provenance.source == "" then
      error("TechnologyQualityAssessment metric provenance is invalid: " .. field, 2)
    end
  end
  if not STATUSES[record.status] or type(record.review_reasons) ~= "table"
    or type(record.evidence_sha256) ~= "table" then
    error("TechnologyQualityAssessment decision material is invalid.", 2)
  end
  if record.measurement_status == "INCOMPLETE" and record.status == "PASS" then
    error("Incomplete TechnologyQualityAssessment cannot pass.", 2)
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
  values.metric_provenance = values.metric_provenance or {}
  local incomplete = false
  for _, field in ipairs(REQUIRED_NUMBERS) do
    values[field] = tonumber(values[field])
    local provenance = values.metric_provenance[field]
    if not provenance then
      provenance = {source = "not-measured", measurement_status = "INCOMPLETE", witnesses = {}}
      values.metric_provenance[field] = provenance
    end
    if values[field] == nil or provenance.measurement_status ~= "COMPLETE" then incomplete = true end
  end
  values.measurement_status = incomplete and "INCOMPLETE" or "COMPLETE"
  values.thresholds = values.thresholds or {}
  local requested_status = values.status or "PASS"
  values.status = incomplete and (STATUS_SEVERITY[requested_status] > STATUS_SEVERITY.REVIEW_REQUIRED
    and requested_status or "REVIEW_REQUIRED") or requested_status
  values.assessment_fingerprint = fingerprint.of(material(values))
  M.validate(values)
  return values
end

return M
