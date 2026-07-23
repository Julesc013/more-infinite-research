local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 2

local DIMENSION_VALUES = {
  execution = {NOT_EXECUTED = true, PLANNED = true, APPLIED = true, FAILED = true},
  safety = {QUALIFIED = true, REVIEW_REQUIRED = true, FAILED = true},
  review = {NOT_REQUIRED = true, REQUIRED = true, COMPLETE = true},
  promotion = {NOT_APPLICABLE = true, PROVISIONAL = true, PROMOTED = true, BLOCKED = true},
  release = {ELIGIBLE = true, REVIEW_REQUIRED = true, BLOCKED = true}
}

local PROJECTION_CLASSES = {
  "accepted_candidates", "rejected_candidates", "review_required_candidates", "provider_claims",
  "base_continuations", "quality_dispositions", "promotion_dispositions", "sanitation_dispositions"
}

local function material(record)
  local out = deepcopy(record)
  out.result_fingerprint = nil
  return out
end

local function derived_status(dimensions)
  if dimensions.execution == "FAILED" or dimensions.safety == "FAILED"
    or dimensions.promotion == "BLOCKED" or dimensions.release == "BLOCKED" then
    return "FAIL"
  end
  if dimensions.safety == "REVIEW_REQUIRED" or dimensions.review == "REQUIRED"
    or dimensions.release == "REVIEW_REQUIRED" or dimensions.promotion == "PROVISIONAL" then
    return "REVIEW_REQUIRED"
  end
  return "PASS"
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerResult" then
    error("CompilerResult schema 2 record is required.", 2)
  end
  for _, field in ipairs({
    "input_fingerprint", "technology_catalog_fingerprint", "generation_plan_fingerprint",
    "compilation_plan_fingerprint", "qualification_fingerprint", "status"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerResult field is required: " .. field, 2)
    end
  end
  if type(record.dimensions) ~= "table" or type(record.operation_fingerprints) ~= "table"
    or type(record.disposition_counts) ~= "table" or type(record.disposition_fingerprints) ~= "table" then
    error("CompilerResult multidimensional disposition material is required.", 2)
  end
  for name, values in pairs(DIMENSION_VALUES) do
    if not values[record.dimensions[name]] then
      error("CompilerResult dimension is invalid: " .. name, 2)
    end
  end
  for _, class in ipairs(PROJECTION_CLASSES) do
    if type(record[class]) ~= "table" then error("CompilerResult projection is required: " .. class, 2) end
    if record.disposition_counts[class] ~= #record[class]
      or record.disposition_fingerprints[class] ~= fingerprint.of(record[class]) then
      error("CompilerResult disposition summary differs: " .. class, 2)
    end
  end
  if record.status ~= derived_status(record.dimensions) then
    error("CompilerResult scalar status differs from its dimensions.", 2)
  end
  if record.result_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerResult fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "CompilerResult"
  record.operation_fingerprints = record.operation_fingerprints or {}
  record.dimensions = record.dimensions or {
    execution = "PLANNED",
    safety = "QUALIFIED",
    review = "NOT_REQUIRED",
    promotion = "NOT_APPLICABLE",
    release = "ELIGIBLE"
  }
  record.disposition_counts = {}
  record.disposition_fingerprints = {}
  for _, class in ipairs(PROJECTION_CLASSES) do
    record[class] = record[class] or {}
    record.disposition_counts[class] = #record[class]
    record.disposition_fingerprints[class] = fingerprint.of(record[class])
  end
  record.status = derived_status(record.dimensions)
  record.result_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.schema_authority()
  local out = {schema = SCHEMA, dimensions = {}, projection_classes = deepcopy(PROJECTION_CLASSES)}
  for name, values in pairs(DIMENSION_VALUES) do
    out.dimensions[name] = {}
    for value in pairs(values) do table.insert(out.dimensions[name], value) end
    table.sort(out.dimensions[name])
  end
  return out
end

function M.compatibility_projection(record)
  M.validate(record)
  local out = {
    schema = 1,
    record_type = "CompilerResult",
    input_fingerprint = record.input_fingerprint,
    technology_catalog_fingerprint = record.technology_catalog_fingerprint,
    generation_plan_fingerprint = record.generation_plan_fingerprint,
    compilation_plan_fingerprint = record.compilation_plan_fingerprint,
    qualification_fingerprint = record.qualification_fingerprint,
    operation_fingerprints = deepcopy(record.operation_fingerprints),
    rejected_candidates = deepcopy(record.rejected_candidates),
    status = record.status,
    authoritative_result_fingerprint = record.result_fingerprint
  }
  local projection_material = deepcopy(out)
  projection_material.result_fingerprint = nil
  out.result_fingerprint = fingerprint.of(projection_material)
  return out
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
