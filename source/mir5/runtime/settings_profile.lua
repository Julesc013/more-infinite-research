-- Public settings-profile facade. Bootstrap owns remote registration.
local settings_catalog = require("research.settings")
local profile_codec = require("research.settings_profile")

local function startup_settings()
  return settings and settings.startup or {}
end

local function metadata()
  local mods = script and script.active_mods or {}
  return {
    mir_version = mods["more-infinite-research"],
    factorio_version = helpers and helpers.game_version or nil,
    import_setting = settings_catalog.import_setting_name
  }
end

local function export_string(options)
  if type(options) ~= "table" then options = {} end
  local effective = settings_catalog.effective_values(startup_settings(), helpers)
  local profile = profile_codec.current_profile({
    names = settings_catalog.registered_names(),
    value_resolver = function(name) return effective[name] end,
    is_default = settings_catalog.is_default_value,
    compact = options.compact == true,
    metadata = metadata()
  })
  return profile_codec.encode(profile, helpers)
end

local function validate_string(text)
  local profile, err = profile_codec.decode(text, helpers)
  if not profile then return {valid = false, error = err} end
  local status = settings_catalog.profile_status(profile, startup_settings())
  return {
    valid = true,
    recognized = status.recognized,
    invalid = status.invalid,
    unknown = status.unknown,
    import_setting = settings_catalog.import_setting_name
  }
end

return {export_string = export_string, validate_string = validate_string}
