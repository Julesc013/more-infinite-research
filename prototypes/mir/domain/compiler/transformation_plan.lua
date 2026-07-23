local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")

local M = {}
local SCHEMA = 2

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

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "TransformationPlan"
    or type(record.phase) ~= "string" or type(record.execution_mode) ~= "string"
    or type(record.operations) ~= "table" or type(record.operation_counts) ~= "table"
    or type(record.operation_fingerprints) ~= "table" then
    error("TransformationPlan schema 2 record is required.", 2)
  end
  local previous, counts, seen, operation_fingerprints = nil, {}, {}, {}
  for _, operation in ipairs(record.operations) do
    operation_contract.validate(operation)
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
  if fingerprint.of(counts) ~= fingerprint.of(record.operation_counts)
    or fingerprint.of(operation_fingerprints) ~= fingerprint.of(record.operation_fingerprints)
    or record.plan_fingerprint ~= fingerprint.of(material(record)) then
    error("TransformationPlan fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "TransformationPlan"
  record.execution_mode = record.execution_mode or "SAFE"
  record.operations = record.operations or {}
  table.sort(record.operations, function(left, right) return left.operation_id < right.operation_id end)
  record.operation_counts = {}
  record.operation_fingerprints = {}
  for _, operation in ipairs(record.operations) do
    operation_contract.validate(operation)
    record.operation_counts[operation.action] = (record.operation_counts[operation.action] or 0) + 1
    record.operation_fingerprints[operation.operation_id] = operation.operation_fingerprint
  end
  record.plan_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
