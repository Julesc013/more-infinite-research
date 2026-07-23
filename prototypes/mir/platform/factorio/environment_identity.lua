local fingerprint = require("prototypes.mir.core.fingerprint")
local environment_identity = require("prototypes.mir.domain.environment_identity")
local mods = require("prototypes.mir.platform.factorio.mods")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

local M = {}

function M.current(options)
  options = options or {}
  local profile = target_profiles.current()
  return environment_identity.new({
    factorio_line = tostring(profile.factorio_version),
    target_profile_fingerprint = fingerprint.of(profile),
    loaded_mod_closure = mods.snapshot(),
    fixture_profile = options.fixture_profile,
    configuration_fingerprint = options.configuration_fingerprint or fingerprint.of({})
  })
end

return M
