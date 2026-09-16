local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function material(record)
  local out = deepcopy(record)
  out.environment_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= 1
    or record.record_type ~= "QualificationEnvironmentIdentity" then
    error("QualificationEnvironmentIdentity schema 1 record is required.", 2)
  end
  for _, field in ipairs({
    "candidate_sha256", "factorio_binary_sha256", "runner_identity", "verifier_sha256",
    "required_test_set_sha256", "plan_material_sha256", "trust_class"
  }) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("QualificationEnvironmentIdentity field is required: " .. field, 2)
    end
  end
  if record.environment_fingerprint ~= fingerprint.of(material(record)) then
    error("QualificationEnvironmentIdentity fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  local record = deepcopy(values or {})
  record.schema = 1
  record.record_type = "QualificationEnvironmentIdentity"
  record.environment_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

return M
