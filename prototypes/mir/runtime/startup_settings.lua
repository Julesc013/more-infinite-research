local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")

local M = {}

local function raw_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  return setting and setting.value or nil
end

local function imported_profile()
  local text = raw_setting(profile_codec.import_setting_name)
  if text == nil or text == "" then return nil end
  return profile_codec.decode(text)
end

function M.raw(name)
  return raw_setting(name)
end

function M.get(name)
  local profile = imported_profile()
  if profile and name ~= profile_codec.import_setting_name
    and settings and settings.startup and settings.startup[name] ~= nil then
    local imported = profile.settings and profile.settings[name]
    if imported ~= nil and settings_catalog.validate_value(name, imported) then
      return imported
    end
  end
  return raw_setting(name)
end

return M
