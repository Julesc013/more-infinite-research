local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 2
local ACTIONS = {create = true, patch = true}

local function material(record)
  local out = deepcopy(record)
  out.operation_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "TransformationOperation"
    or not ACTIONS[record.action] or type(record.operation_id) ~= "string" or record.operation_id == ""
    or type(record.phase) ~= "string" or record.phase == ""
    or type(record.subject) ~= "table" or record.subject.type ~= "technology"
    or type(record.subject.id) ~= "string" or record.subject.id == ""
    or type(record.payload) ~= "table" or type(record.evidence) ~= "table"
    or type(record.expected_before_snapshot) ~= "table"
    or type(record.expected_after_projection) ~= "table"
    or type(record.allowed_delta) ~= "table" or type(record.source) ~= "table" then
    error("TransformationOperation schema 2 complete technology envelope is required.", 2)
  end
  for _, field in ipairs({
    "expected_before_fingerprint", "expected_after_fingerprint", "authority_fingerprint",
    "qualification_fingerprint", "operation_fingerprint"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TransformationOperation field is required: " .. field, 2)
    end
  end
  if type(record.source.candidate_id) ~= "string" or record.source.candidate_id == ""
    or type(record.source.alternative_id) ~= "string" or record.source.alternative_id == "" then
    error("TransformationOperation exact source candidate and alternative are required.", 2)
  end
  if record.expected_before_fingerprint ~= fingerprint.of(record.expected_before_snapshot)
    or record.expected_after_fingerprint ~= fingerprint.of(record.expected_after_projection)
    or record.operation_fingerprint ~= fingerprint.of(material(record)) then
    error("TransformationOperation fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "TransformationOperation"
  record.evidence = record.evidence or {}
  record.allowed_delta = record.allowed_delta or {}
  record.expected_before_snapshot = record.expected_before_snapshot or {}
  record.expected_after_projection = record.expected_after_projection or {}
  record.expected_before_fingerprint = fingerprint.of(record.expected_before_snapshot)
  record.expected_after_fingerprint = fingerprint.of(record.expected_after_projection)
  record.operation_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

return M
