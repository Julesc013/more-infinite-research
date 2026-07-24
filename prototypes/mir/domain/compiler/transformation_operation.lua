local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")

local M = {}
local SCHEMA = 2
local ACTIONS = {create = true, patch = true}
local authority = trusted_record.new("TransformationOperation")

local function material(record)
  local out = {}
  for key, value in pairs(record) do
    if key ~= "operation_fingerprint" then out[key] = value end
  end
  return out
end

local function trust_identity(record)
  return {
    schema = record.schema,
    operation_id = record.operation_id,
    expected_before_fingerprint = record.expected_before_fingerprint,
    expected_after_fingerprint = record.expected_after_fingerprint,
    operation_fingerprint = record.operation_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.operation_id == registered.operation_id
    and record.expected_before_fingerprint == registered.expected_before_fingerprint
    and record.expected_after_fingerprint == registered.expected_after_fingerprint
    and record.operation_fingerprint == registered.operation_fingerprint
end

local function verify(record, options)
  options = options or {}
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
  if options.verify_fingerprints ~= false then
    if record.expected_before_fingerprint ~= fingerprint.of(record.expected_before_snapshot)
      or record.expected_after_fingerprint ~= fingerprint.of(record.expected_after_projection)
      or record.operation_fingerprint ~= fingerprint.of(material(record)) then
      error("TransformationOperation fingerprint is invalid.", 2)
    end
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

function M.new(values)
  values = values or {}
  local record = {}
  for key, value in pairs(values) do
    if key ~= "payload" and key ~= "evidence" then record[key] = deepcopy(value) end
  end
  record.payload = {}
  for key, value in pairs(values.payload or {}) do
    record.payload[key] = key == "technology_design" and value or deepcopy(value)
  end
  record.evidence = {}
  for key, value in pairs(values.evidence or {}) do
    record.evidence[key] = key == "gates" and value or deepcopy(value)
  end
  record.schema = SCHEMA
  record.record_type = "TransformationOperation"
  record.evidence = record.evidence or {}
  record.allowed_delta = record.allowed_delta or {}
  record.expected_before_snapshot = record.expected_before_snapshot or {}
  record.expected_after_projection = record.expected_after_projection or {}
  record.expected_before_fingerprint = fingerprint.of(record.expected_before_snapshot)
  record.expected_after_fingerprint = fingerprint.of(record.expected_after_projection)
  record.operation_fingerprint = fingerprint.of(material(record))
  verify(record, {verify_fingerprints = false})
  return authority.register(record, trust_identity(record))
end

return M
