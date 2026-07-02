local defaults = require("defaults")
local presets = require("prototypes.settings-presets")

local R = {}

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
end

local function preset_mode()
  local mode = startup_setting("mir-settings-mode")
  if not mode or not presets.modes[mode] then return presets.default_mode end
  return mode
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

local function preset_stream_enabled(key, fallback)
  local mode = preset_mode()
  if mode == "custom" then return fallback == true end

  local preset = presets.modes[mode]
  local entry = preset and preset.streams and preset.streams[key]
  if type(entry) == "boolean" then return entry end
  if type(entry) == "table" and entry.enabled ~= nil then return entry.enabled == true end
  return fallback == true
end

local function enable_policy(key)
  local policy = startup_setting("mir-enable-policy-" .. key)
  if policy == "force-enabled" or policy == "Force enabled" then return "force-enabled" end
  if policy == "force-disabled" or policy == "Force disabled" then return "force-disabled" end
  return "use-settings-mode"
end

function R.mode()
  return preset_mode()
end

function R.stream_enabled(key)
  local policy = enable_policy(key)
  if policy == "force-enabled" then return true end
  if policy == "force-disabled" then return false end

  local fallback = stream_default_enabled(key)
  if preset_mode() ~= "custom" then
    return preset_stream_enabled(key, fallback)
  end

  local setting = startup_setting("ips-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

return R
