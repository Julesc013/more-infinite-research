local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local SCHEMA = 1

local function material(record)
  local out = deepcopy(record)
  out.environment_fingerprint = nil
  return out
end

function M.validate(record)
  if type(record) ~= "table" or record.schema ~= SCHEMA or record.record_type ~= "EnvironmentIdentity"
    or type(record.factorio_line) ~= "string" or record.factorio_line == ""
    or type(record.target_profile_fingerprint) ~= "string" or record.target_profile_fingerprint == ""
    or type(record.loaded_mod_closure) ~= "table" then
    error("EnvironmentIdentity schema 1 exact environment is required.", 2)
  end
  local previous, seen = nil, {}
  for _, loaded_mod in ipairs(record.loaded_mod_closure) do
    if type(loaded_mod) ~= "table" or type(loaded_mod.id) ~= "string" or loaded_mod.id == ""
      or type(loaded_mod.version) ~= "string" or loaded_mod.version == "" or seen[loaded_mod.id]
      or (previous and previous > loaded_mod.id) then
      error("EnvironmentIdentity mod closure must contain sorted exact id/version rows.", 2)
    end
    seen[loaded_mod.id], previous = true, loaded_mod.id
  end
  if record.environment_fingerprint ~= fingerprint.of(material(record)) then
    error("EnvironmentIdentity fingerprint is invalid.", 2)
  end
  return true
end

function M.new(values)
  values = deepcopy(values or {})
  local loaded_mod_closure = {}
  for id, version in pairs(values.loaded_mod_closure or {}) do
    table.insert(loaded_mod_closure, {id = tostring(id), version = tostring(version)})
  end
  table.sort(loaded_mod_closure, function(left, right) return left.id < right.id end)
  local record = {
    schema = SCHEMA,
    record_type = "EnvironmentIdentity",
    factorio_line = values.factorio_line,
    target_profile_fingerprint = values.target_profile_fingerprint,
    loaded_mod_closure = loaded_mod_closure,
    fixture_profile = values.fixture_profile,
    configuration_fingerprint = values.configuration_fingerprint or fingerprint.of({})
  }
  record.environment_fingerprint = fingerprint.of(material(record))
  M.validate(record)
  return record
end

return M
