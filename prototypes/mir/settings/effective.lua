local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")

local M = {}

local import_loaded = false
local import_profile = nil
local import_error = nil

local function raw_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function setting_exists(name)
  return settings and settings.startup and settings.startup[name] ~= nil
end

local function load_import_profile()
  if import_loaded then return import_profile end
  import_loaded = true

  local text = raw_setting(profile_codec.import_setting_name)
  if text == nil or text == "" then return nil end

  local profile, err = profile_codec.decode(text)
  if not profile then
    import_error = err
    if log then
      log("[more-infinite-research] Ignoring invalid MIR settings profile import: " .. tostring(err))
    end
    return nil
  end

  import_profile = profile
  return import_profile
end

function M.raw(name)
  return raw_setting(name)
end

function M.get(name)
  local profile = load_import_profile()
  if profile and name ~= profile_codec.import_setting_name and setting_exists(name) then
    local imported = profile.settings and profile.settings[name]
    if imported ~= nil and settings_catalog.validate_value(name, imported) then
      return imported
    end
  end

  return raw_setting(name)
end

function M.import_status()
  load_import_profile()

  if import_profile then
    local recognized, unknown, invalid = profile_codec.count_recognized_settings(import_profile)
    return {
      active = true,
      recognized = recognized,
      unknown = unknown,
      invalid = invalid,
      error = nil
    }
  end

  return {
    active = false,
    recognized = 0,
    unknown = 0,
    invalid = 0,
    error = import_error
  }
end

function M.active_profile()
  return load_import_profile()
end

return M
