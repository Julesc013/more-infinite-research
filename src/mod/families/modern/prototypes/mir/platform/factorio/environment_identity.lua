local fingerprint = require("prototypes.mir.core.fingerprint")
local environment_identity = require("prototypes.mir.domain.environment_identity")
local mods = require("prototypes.mir.platform.factorio.mods")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")

local M = {}

function M.current(options)
  options = options or {}
  local profile = target_profiles.current()
  local settings_snapshot = options.effective_settings or {}
  local policy_snapshot = options.policy_snapshot or {}
  return environment_identity.new({
    factorio_line = tostring(profile.factorio_version),
    target_profile_fingerprint = fingerprint.of(profile),
    loaded_mod_closure = mods.snapshot(),
    fixture_profile = options.fixture_profile,
    startup_settings_fingerprint = settings_snapshot.settings_fingerprint
      or policy_snapshot.settings_fingerprint or fingerprint.of({}),
    imported_profile_fingerprint = fingerprint.of(settings_snapshot.imported_profile or {}),
    compatibility_policy_fingerprint = policy_snapshot.compatibility_policy_fingerprint or fingerprint.of({}),
    promotion_authority_fingerprint = policy_snapshot.promotion_authority_fingerprint or fingerprint.of({})
  })
end

return M
