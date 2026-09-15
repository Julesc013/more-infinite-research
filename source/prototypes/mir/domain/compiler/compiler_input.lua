local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local environment_identity = require("prototypes.mir.domain.environment_identity")

local M = {}
local authority = trusted_record.new("CompilerInput")
local SCHEMA = 2

local function material(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    source_fingerprints = record.source_fingerprints,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    runtime_environment_fingerprint = record.runtime_environment_fingerprint,
    input_sanitation_fingerprint = record.input_sanitation_fingerprint
  }
end

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    compilation_snapshot_fingerprint = record.compilation_snapshot_fingerprint,
    policy_fingerprint = record.policy_fingerprint,
    runtime_environment_fingerprint = record.runtime_environment_fingerprint,
    input_fingerprint = record.input_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.compilation_snapshot_fingerprint == registered.compilation_snapshot_fingerprint
    and record.policy_fingerprint == registered.policy_fingerprint
    and record.runtime_environment_fingerprint == registered.runtime_environment_fingerprint
    and record.input_fingerprint == registered.input_fingerprint
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerInput" then
    error("CompilerInput schema 2 record is required.", 2)
  end
  for _, field in ipairs({
    "compilation_snapshot_fingerprint", "policy_fingerprint", "runtime_environment_fingerprint",
    "input_sanitation_fingerprint"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerInput field is required: " .. field, 2)
    end
  end
  if type(record.source_fingerprints) ~= "table" then
    error("CompilerInput source fingerprints are required.", 2)
  end
  if options.trusted_children then
    compilation_snapshot.assert_trusted(record.compilation_snapshot)
    policy_snapshot.assert_trusted(record.policy_snapshot)
    environment_identity.assert_trusted(record.runtime_environment)
  else
    compilation_snapshot.verify_untrusted(record.compilation_snapshot)
    policy_snapshot.verify_untrusted(record.policy_snapshot)
    environment_identity.verify_untrusted(record.runtime_environment)
  end
  if record.compilation_snapshot.snapshot_fingerprint ~= record.compilation_snapshot_fingerprint
    or record.policy_snapshot.policy_fingerprint ~= record.policy_fingerprint
    or record.runtime_environment.environment_fingerprint ~= record.runtime_environment_fingerprint then
    error("CompilerInput bound authority fingerprint differs from its record.", 2)
  end
  if options.verify_fingerprint ~= false
    and record.input_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerInput fingerprint is invalid.", 2)
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
  local record = {
    schema = SCHEMA,
    record_type = "CompilerInput",
    source_fingerprints = values.source_fingerprints or {},
    compilation_snapshot = values.compilation_snapshot,
    policy_snapshot = values.policy_snapshot,
    runtime_environment = values.runtime_environment,
    input_sanitation_fingerprint = values.input_sanitation_fingerprint or fingerprint.of({})
  }
  record.compilation_snapshot_fingerprint = record.compilation_snapshot
    and record.compilation_snapshot.snapshot_fingerprint
  record.policy_fingerprint = record.policy_snapshot and record.policy_snapshot.policy_fingerprint
  record.runtime_environment_fingerprint = record.runtime_environment
    and record.runtime_environment.environment_fingerprint
  if compilation_snapshot.is_trusted(record.compilation_snapshot) then
    compilation_snapshot.assert_trusted(record.compilation_snapshot)
  else
    compilation_snapshot.verify_untrusted(record.compilation_snapshot)
  end
  if policy_snapshot.is_trusted(record.policy_snapshot) then
    policy_snapshot.assert_trusted(record.policy_snapshot)
  else
    policy_snapshot.verify_untrusted(record.policy_snapshot)
  end
  if environment_identity.is_trusted(record.runtime_environment) then
    environment_identity.assert_trusted(record.runtime_environment)
  else
    environment_identity.verify_untrusted(record.runtime_environment)
  end
  record.input_fingerprint = fingerprint.of(material(record))
  verify(record, {trusted_children = true, verify_fingerprint = false})
  return authority.register(record, trust_identity(record))
end

function M.compatibility_projection(record, generation_plan_fingerprint)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  local environment = environment_identity.compatibility_projection(record.runtime_environment)
  local out = {
    schema = 1,
    record_type = "CompilerInput",
    source_fingerprints = deepcopy(record.source_fingerprints),
    environment_identity = environment,
    environment_fingerprint = environment.environment_fingerprint,
    target_profile_fingerprint = record.runtime_environment.target_profile_fingerprint,
    generation_plan_fingerprint = generation_plan_fingerprint or record.compilation_snapshot_fingerprint,
    input_sanitation_fingerprint = record.input_sanitation_fingerprint,
    authoritative_input_fingerprint = record.input_fingerprint
  }
  local fp_material = deepcopy(out)
  fp_material.input_fingerprint = nil
  out.input_fingerprint = fingerprint.of(fp_material)
  return out
end

function M.snapshot(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  authority.count_snapshot()
  authority.count_full_copy()
  local out = deepcopy(record)
  out.compilation_snapshot = compilation_snapshot.snapshot(record.compilation_snapshot)
  return out
end

return M
