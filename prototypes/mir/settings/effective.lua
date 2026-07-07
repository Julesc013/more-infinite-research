local profile_codec = require("prototypes.mir.settings.profile_codec")

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

local function type_matches(value, fallback)
  if fallback == nil then return true end

  local expected = type(fallback)
  if expected == "number" then return type(value) == "number" end
  return type(value) == expected
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
    if imported ~= nil and type_matches(imported, raw_setting(name)) then
      return imported
    end
  end

  return raw_setting(name)
end

function M.import_status()
  load_import_profile()

  if import_profile then
    local recognized, unknown = profile_codec.count_recognized_settings(import_profile)
    return {
      active = true,
      recognized = recognized,
      unknown = unknown,
      error = nil
    }
  end

  return {
    active = false,
    recognized = 0,
    unknown = 0,
    error = import_error
  }
end

function M.active_profile()
  return load_import_profile()
end

return M
