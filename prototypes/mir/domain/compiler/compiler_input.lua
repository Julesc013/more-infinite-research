local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1

local function material(record)
  local out = deepcopy(record)
  out.input_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "CompilerInput" then
    error("CompilerInput schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "environment_fingerprint", "target_profile_fingerprint", "generation_plan_fingerprint",
    "input_sanitation_fingerprint"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("CompilerInput field is required: " .. field, 2)
    end
  end
  if type(record.source_fingerprints) ~= "table" or type(record.environment_identity) ~= "table" then
    error("CompilerInput source and environment material are required.", 2)
  end
  if record.environment_identity.environment_fingerprint
      and record.environment_identity.environment_fingerprint ~= record.environment_fingerprint then
    error("CompilerInput environment fingerprint differs from EnvironmentIdentity.", 2)
  end
  if record.environment_identity.target_profile_fingerprint
      and record.environment_identity.target_profile_fingerprint ~= record.target_profile_fingerprint then
    error("CompilerInput target profile differs from EnvironmentIdentity.", 2)
  end
  if record.input_fingerprint ~= fingerprint.of(material(record)) then
    error("CompilerInput fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = SCHEMA
  record.record_type = "CompilerInput"
  record.source_fingerprints = record.source_fingerprints or {}
  record.environment_identity = record.environment_identity or {schema = 1, kind = "unspecified"}
  record.environment_fingerprint = record.environment_fingerprint or fingerprint.of(record.environment_identity)
  record.target_profile_fingerprint = record.target_profile_fingerprint or "unspecified"
  record.generation_plan_fingerprint = record.generation_plan_fingerprint or "unspecified"
  record.input_sanitation_fingerprint = record.input_sanitation_fingerprint or fingerprint.of({})
  record.input_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

function M.snapshot(record)
  M.validate(record)
  return deepcopy(record)
end

return M
