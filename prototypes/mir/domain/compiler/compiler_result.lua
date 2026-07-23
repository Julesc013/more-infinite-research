local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1

local function material(record)
  local out = deepcopy(record)
  out.result_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerResult" then
    error("CompilerResult schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "input_fingerprint", "technology_catalog_fingerprint", "generation_plan_fingerprint",
    "compilation_plan_fingerprint", "qualification_fingerprint", "status"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerResult field is required: " .. field, 2)
    end
  end
  if record.status ~= "PASS" and record.status ~= "REVIEW_REQUIRED" and record.status ~= "FAIL" then
    error("CompilerResult status is invalid.", 2)
  end
  if type(record.operation_fingerprints) ~= "table" or type(record.rejected_candidates) ~= "table" then
    error("CompilerResult operation and rejection projections are required.", 2)
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
  record.rejected_candidates = record.rejected_candidates or {}
  record.status = record.status or "PASS"
  record.result_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
