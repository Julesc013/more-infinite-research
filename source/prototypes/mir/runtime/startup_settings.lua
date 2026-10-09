local profile_codec = require("prototypes.mir.settings.profile_codec")
local settings_catalog = require("prototypes.mir.settings.catalog")

local M = {}
local decoded_import

local function raw_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting ~= nil then return setting.value end
  return nil
end

local function imported_profile()
  local text = raw_setting(profile_codec.import_setting_name)
  if text == nil or text == "" then
    decoded_import = nil
    return nil
  end
  if type(text) ~= "string" then
    decoded_import = nil
    return profile_codec.decode(text)
  end

  local json_to_table = helpers and helpers.json_to_table
  local decode_string = helpers and helpers.decode_string
  local encode_string = helpers and helpers.encode_string
  if decoded_import and decoded_import.text == text
    and decoded_import.helpers == helpers
    and decoded_import.json_to_table == json_to_table
    and decoded_import.decode_string == decode_string
    and decoded_import.encode_string == encode_string then
    return decoded_import.profile
  end

  -- Retain only the current decode, including failures. Registration and value
  -- validation remain live in get(); the decoded table never leaves this module.
  decoded_import = {
    text = text, helpers = helpers, json_to_table = json_to_table,
    decode_string = decode_string, encode_string = encode_string,
    profile = profile_codec.decode(text)
  }
  return decoded_import.profile
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
