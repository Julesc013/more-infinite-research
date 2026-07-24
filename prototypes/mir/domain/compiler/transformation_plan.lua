local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")

local M = {}
local SCHEMA = 2
local authority = trusted_record.new("TransformationPlan")

local function material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    phase = record.phase,
    execution_mode = record.execution_mode,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    operations = record.operations,
    operation_counts = record.operation_counts,
    operation_fingerprints = record.operation_fingerprints
  }
end

local function trust_identity(record)
  return {
    schema = record.schema,
    phase = record.phase,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    plan_fingerprint = record.plan_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.phase == registered.phase
    and record.compilation_snapshot_fingerprint == registered.compilation_snapshot_fingerprint
    and record.policy_fingerprint == registered.policy_fingerprint
    and record.plan_fingerprint == registered.plan_fingerprint
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "TransformationPlan"
    or type(record.phase) ~= "string" or type(record.execution_mode) ~= "string"
    or type(record.operations) ~= "table" or type(record.operation_counts) ~= "table"
    or type(record.operation_fingerprints) ~= "table" then
    error("TransformationPlan schema 2 record is required.", 2)
  end
  local previous, counts, seen, operation_fingerprints = nil, {}, {}, {}
  for _, operation in ipairs(record.operations) do
    if options.trusted_children then operation_contract.assert_trusted(operation)
    else operation_contract.verify_untrusted(operation) end
    if previous and previous > operation.operation_id then
      error("TransformationPlan operations must be canonically ordered.", 2)
    end
    if seen[operation.operation_id] then
      error("TransformationPlan operation id is duplicated: " .. operation.operation_id, 2)
    end
    seen[operation.operation_id] = true
    previous = operation.operation_id
    counts[operation.action] = (counts[operation.action] or 0) + 1
    operation_fingerprints[operation.operation_id] = operation.operation_fingerprint
  end
  if options.verify_fingerprints ~= false then
    if fingerprint.of(counts) ~= fingerprint.of(record.operation_counts)
      or fingerprint.of(operation_fingerprints) ~= fingerprint.of(record.operation_fingerprints)
      or record.plan_fingerprint ~= fingerprint.of(material(record)) then
      error("TransformationPlan fingerprint is invalid.", 2)
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
    if key ~= "operations" then record[key] = deepcopy(value) end
  end
  record.operations = {}
  for index, operation in ipairs(values.operations or {}) do record.operations[index] = operation end
  record.schema = SCHEMA
  record.record_type = "TransformationPlan"
  record.execution_mode = record.execution_mode or "SAFE"
  record.operations = record.operations or {}
  table.sort(record.operations, function(left, right) return left.operation_id < right.operation_id end)
  record.operation_counts = {}
  record.operation_fingerprints = {}
  for _, operation in ipairs(record.operations) do
    operation_contract.assert_trusted(operation)
    record.operation_counts[operation.action] = (record.operation_counts[operation.action] or 0) + 1
    record.operation_fingerprints[operation.operation_id] = operation.operation_fingerprint
  end
  record.plan_fingerprint = fingerprint.of(material(record))
  verify(record, {trusted_children = true, verify_fingerprints = false})
  return authority.register(record, trust_identity(record))
end

function M.snapshot(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  return deepcopy(record)
end

return M
