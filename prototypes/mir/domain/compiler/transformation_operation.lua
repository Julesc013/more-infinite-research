local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local ACTIONS = {create = true, patch = true, delete = true}

local function material(record)
  local out = deepcopy(record)
  out.operation_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= 1 or record.record_type ~= "TransformationOperation"
    or not ACTIONS[record.action] or type(record.operation_id) ~= "string" or record.operation_id == ""
    or type(record.phase) ~= "string" or record.phase == ""
    or type(record.subject) ~= "table" or type(record.subject.type) ~= "string"
    or type(record.subject.id) ~= "string" or record.subject.id == ""
    or type(record.payload) ~= "table" or type(record.evidence) ~= "table" then
    error("TransformationOperation schema 1 complete envelope is required.", 2)
  end
  for _, field in ipairs({"precondition_fingerprint", "expected_output_fingerprint", "authority_fingerprint"}) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("TransformationOperation field is required: " .. field, 2)
    end
  end
  if record.expected_output_fingerprint ~= fingerprint.of(record.payload)
    or record.operation_fingerprint ~= fingerprint.of(material(record)) then
    error("TransformationOperation fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = 1
  record.record_type = "TransformationOperation"
  record.evidence = record.evidence or {}
  record.precondition_fingerprint = record.precondition_fingerprint or fingerprint.of({})
  record.authority_fingerprint = record.authority_fingerprint or fingerprint.of({})
  record.expected_output_fingerprint = fingerprint.of(record.payload or {})
  record.operation_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

return M
