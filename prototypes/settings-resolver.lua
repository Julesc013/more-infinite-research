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

local function lookup_default(kind, key, field, spec, fallback)
  local group = kind == "base" and defaults.base_extensions or defaults.streams
  local entry = group and group[key]
  if entry and entry[field] ~= nil then return entry[field] end
  if spec and spec[field] ~= nil then return spec[field] end
  local shared = defaults.shared or {}
  if kind ~= "base" and shared[field] ~= nil then return shared[field] end
  return fallback
end

local function preset_entry(kind, key)
  local mode = preset_mode()
  if mode == "custom" then return nil end

  local preset = presets.modes[mode]
  local group = kind == "base" and preset.base_extensions or preset.streams
  return group and group[key] or nil
end

local function preset_enabled(kind, key, fallback)
  local entry = preset_entry(kind, key)
  if type(entry) == "boolean" then return entry end
  if type(entry) == "table" and entry.enabled ~= nil then return entry.enabled == true end
  return fallback == true
end

local function enable_policy(kind, key)
  local policy = startup_setting("mir-enable-policy-" .. key)
  if policy == "force-enabled" or policy == "Force enabled" then return "force-enabled" end
  if policy == "force-disabled" or policy == "Force disabled" then return "force-disabled" end
  return "use-settings-mode"
end

function R.mode()
  return preset_mode()
end

function R.stream_default_enabled(key, spec)
  return lookup_default("stream", key, "enabled", spec, true) == true
end

function R.base_default_enabled(key, spec)
  return lookup_default("base", key, "enabled", spec, true) == true
end

function R.stream_enabled(key, spec)
  local policy = enable_policy("stream", key)
  if policy == "force-enabled" then return true end
  if policy == "force-disabled" then return false end

  local fallback = R.stream_default_enabled(key, spec)
  if preset_mode() ~= "custom" then
    return preset_enabled("stream", key, fallback)
  end

  local setting = startup_setting("ips-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

function R.base_enabled(key, spec)
  local policy = enable_policy("base", key)
  if policy == "force-enabled" then return true end
  if policy == "force-disabled" then return false end

  local fallback = R.base_default_enabled(key, spec)
  if preset_mode() ~= "custom" then
    return preset_enabled("base", key, fallback)
  end

  local setting = startup_setting("mir-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

return R
