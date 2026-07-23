local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local compilation_snapshot = require("prototypes.mir.domain.compiler.compilation_snapshot")
local policy_snapshot = require("prototypes.mir.domain.compiler.policy_snapshot")
local environment_identity = require("prototypes.mir.domain.environment_identity")

local M = {}
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

function M.validate(record)
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
  compilation_snapshot.validate(record.compilation_snapshot)
  policy_snapshot.validate(record.policy_snapshot)
  environment_identity.validate(record.runtime_environment)
  if record.compilation_snapshot.snapshot_fingerprint ~= record.compilation_snapshot_fingerprint
    or record.policy_snapshot.policy_fingerprint ~= record.policy_fingerprint
    or record.runtime_environment.environment_fingerprint ~= record.runtime_environment_fingerprint then
    error("CompilerInput bound authority fingerprint differs from its record.", 2)
  end
  if record.input_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerInput fingerprint is invalid.", 2)
  end
  return true
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
  record.input_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.compatibility_projection(record, generation_plan_fingerprint)
  M.validate(record)
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
  M.validate(record)
  local out = deepcopy(record)
  out.compilation_snapshot = compilation_snapshot.snapshot(record.compilation_snapshot)
  return out
end

return M
