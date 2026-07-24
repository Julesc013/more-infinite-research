local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local trusted_record = require("prototypes.mir.core.trusted_record")

local M = {}
local authority = trusted_record.new("RuntimeEnvironmentIdentity")
local SCHEMA = 2
local REQUIRED_FINGERPRINTS = {
  "target_profile_fingerprint", "startup_settings_fingerprint", "imported_profile_fingerprint",
  "compatibility_policy_fingerprint", "promotion_authority_fingerprint"
}

local function material(record)
  local out = {}
  for key, value in pairs(record or {}) do
    if key ~= "environment_fingerprint" then out[key] = value end
  end
  return out
end

local function normalized_mods(values)
  local rows = {}
  local input = values or {}
  if #input > 0 then
    for _, row in ipairs(input) do
      table.insert(rows, {id = tostring(row.id), version = tostring(row.version)})
    end
  else
    for id, version in pairs(input) do
      table.insert(rows, {id = tostring(id), version = tostring(version)})
    end
  end
  table.sort(rows, function(left, right) return left.id < right.id end)
  return rows
end

local function trust_identity(record)
  return {
    schema = record.schema,
    record_type = record.record_type,
    factorio_line = record.factorio_line,
    target_profile_fingerprint = record.target_profile_fingerprint,
    environment_fingerprint = record.environment_fingerprint
  }
end

local function trust_identity_unchanged(record, registered)
  return record.schema == registered.schema
    and record.record_type == registered.record_type
    and record.factorio_line == registered.factorio_line
    and record.target_profile_fingerprint == registered.target_profile_fingerprint
    and record.environment_fingerprint == registered.environment_fingerprint
end

local function verify(record, options)
  options = options or {}
  if type(record) ~= "table" or record.schema ~= SCHEMA
    or record.record_type ~= "RuntimeEnvironmentIdentity"
    or type(record.factorio_line) ~= "string" or record.factorio_line == ""
    or type(record.loaded_mod_closure) ~= "table" then
    error("RuntimeEnvironmentIdentity schema 2 exact environment is required.", 2)
  end
  for _, field in ipairs(REQUIRED_FINGERPRINTS) do
    if type(record[field]) ~= "string" or record[field] == "" then
      error("RuntimeEnvironmentIdentity field is required: " .. field, 2)
    end
  end
  local previous, seen = nil, {}
  for _, loaded_mod in ipairs(record.loaded_mod_closure) do
    if type(loaded_mod) ~= "table" or type(loaded_mod.id) ~= "string" or loaded_mod.id == ""
      or type(loaded_mod.version) ~= "string" or loaded_mod.version == "" or seen[loaded_mod.id]
      or (previous and previous > loaded_mod.id) then
      error("RuntimeEnvironmentIdentity mod closure must contain sorted exact id/version rows.", 2)
    end
    seen[loaded_mod.id], previous = true, loaded_mod.id
  end
  if options.verify_fingerprints ~= false
    and (record.mod_closure_fingerprint ~= fingerprint.of(record.loaded_mod_closure)
      or record.environment_fingerprint ~= fingerprint.of(material(record))) then
    error("RuntimeEnvironmentIdentity fingerprint is invalid.", 2)
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
  values = deepcopy(values or {})
  local record = {
    schema = SCHEMA,
    record_type = "RuntimeEnvironmentIdentity",
    factorio_line = values.factorio_line,
    target_profile_fingerprint = values.target_profile_fingerprint,
    loaded_mod_closure = normalized_mods(values.loaded_mod_closure),
    fixture_profile = values.fixture_profile,
    startup_settings_fingerprint = values.startup_settings_fingerprint or fingerprint.of({}),
    imported_profile_fingerprint = values.imported_profile_fingerprint or fingerprint.of({}),
    compatibility_policy_fingerprint = values.compatibility_policy_fingerprint or fingerprint.of({}),
    promotion_authority_fingerprint = values.promotion_authority_fingerprint or fingerprint.of({})
  }
  record.mod_closure_fingerprint = fingerprint.of(record.loaded_mod_closure)
  record.environment_fingerprint = fingerprint.of(material(record))
  verify(record, {verify_fingerprints = false})
  return authority.register(record, trust_identity(record))
end

function M.compatibility_projection(record)
  if M.is_trusted(record) then M.assert_trusted(record) else M.verify_untrusted(record) end
  local out = {
    schema = 1,
    record_type = "EnvironmentIdentity",
    factorio_line = record.factorio_line,
    target_profile_fingerprint = record.target_profile_fingerprint,
    loaded_mod_closure = deepcopy(record.loaded_mod_closure),
    fixture_profile = record.fixture_profile,
    configuration_fingerprint = fingerprint.of({
      startup_settings_fingerprint = record.startup_settings_fingerprint,
      imported_profile_fingerprint = record.imported_profile_fingerprint,
      compatibility_policy_fingerprint = record.compatibility_policy_fingerprint,
      promotion_authority_fingerprint = record.promotion_authority_fingerprint
    })
  }
  out.environment_fingerprint = fingerprint.of((function()
    local value = deepcopy(out)
    value.environment_fingerprint = nil
    return value
  end)())
  return out
end

return M
