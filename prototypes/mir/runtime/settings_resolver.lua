local defaults = require("prototypes.mir.settings.defaults")
local effective_settings = require("prototypes.mir.settings.effective")

local R = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function stream_default_enabled(key)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults.enabled ~= nil then
    return stream_defaults.enabled == true
  end

  local shared = defaults.shared or {}
  if shared.enabled ~= nil then return shared.enabled == true end
  return true
end

function R.stream_enabled(key)
  local fallback = stream_default_enabled(key)
  local setting = startup_setting("ips-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

return R
