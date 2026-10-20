local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local operation_contract = require("prototypes.mir.domain.compiler.transformation_operation")

local M = {}
local LEGACY_SCHEMA = 2
local ACTIVE_SCHEMA = 3
local authority = trusted_record.new("TransformationPlan")

local function material(record)
  local out = {
    schema = record.schema,
    record_type = record.record_type,
    phase = record.phase,
    execution_mode = record.execution_mode,
    policy_fingerprint = record.policy_fingerprint,
    operation_counts = record.operation_counts,
    operation_fingerprints = record.operation_fingerprints
  }
  -- Keep the schema-2 canonical payload exactly as its supported generic
  -- import/export contract defined it. Schema-3 labels active identity.
  if record.schema == LEGACY_SCHEMA then
    out.compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint
  else
    out.input_identity = record.input_identity
  end
  return out
end

local function trust_identity(record)
  -- Schema 2 is a supported generic import/export record. Keep its original
  -- scalar authority exactly: it has no active-input cache or surrogate.
  if record.schema == LEGACY_SCHEMA then
    return {
      schema = record.schema,
      phase = record.phase,
      compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
      policy_fingerprint = record.policy_fingerprint,
      plan_fingerprint = record.plan_fingerprint
    }
  end
  return {
    schema = record.schema,
    phase = record.phase,
    input_identity_schema = record.input_identity and record.input_identity.schema,
    input_identity_kind = record.input_identity and record.input_identity.kind,
    input_identity_input_fingerprint = record.input_identity
      and record.input_identity.input_fingerprint,
    input_identity_fingerprint = record.input_identity_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    plan_fingerprint = record.plan_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  if registered.schema == LEGACY_SCHEMA then
    return record.schema == registered.schema
      and record.phase == registered.phase
      and record.compilation_snapshot_fingerprint == registered.compilation_snapshot_fingerprint
      and record.policy_fingerprint == registered.policy_fingerprint
      and record.plan_fingerprint == registered.plan_fingerprint
  end
  return record.schema == registered.schema
    and record.phase == registered.phase
    and record.input_identity and record.input_identity.schema == registered.input_identity_schema
    and record.input_identity.kind == registered.input_identity_kind
    and record.input_identity.input_fingerprint == registered.input_identity_input_fingerprint
    and record.input_identity_fingerprint == registered.input_identity_fingerprint
    and record.policy_fingerprint == registered.policy_fingerprint
    and record.plan_fingerprint == registered.plan_fingerprint
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or (record.schema ~= LEGACY_SCHEMA and record.schema ~= ACTIVE_SCHEMA)
    or record.record_type ~= "TransformationPlan" or type(record.phase) ~= "string"
    or type(record.execution_mode) ~= "string" or type(record.operations) ~= "table"
    or type(record.operation_counts) ~= "table" or type(record.operation_fingerprints) ~= "table" then
    error("TransformationPlan schema 2 or 3 record is required.", 2)
  end
  if record.schema == LEGACY_SCHEMA then
    if type(record.compilation_snapshot_fingerprint) ~= "string" or record.compilation_snapshot_fingerprint == "" then
      error("TransformationPlan schema 2 snapshot binding is required.", 2)
    end
  elseif type(record.input_identity) ~= "table"
    or record.input_identity.schema ~= 1
    or record.input_identity.kind ~= "active-compiler-input-v1"
    or type(record.input_identity.input_fingerprint) ~= "string"
    or record.input_identity.input_fingerprint == ""
    or record.input_identity_fingerprint ~= fingerprint.of(record.input_identity) then
    error("TransformationPlan schema 3 active input identity is required.", 2)
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
  record.schema = values.input_identity and ACTIVE_SCHEMA or LEGACY_SCHEMA
  record.record_type = "TransformationPlan"
  if record.schema == ACTIVE_SCHEMA then
    record.input_identity = deepcopy(values.input_identity)
    record.compilation_snapshot_fingerprint = nil
    record.input_identity_fingerprint = fingerprint.of(record.input_identity)
  else
    record.input_identity = nil
    record.input_identity_fingerprint = nil
  end
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
