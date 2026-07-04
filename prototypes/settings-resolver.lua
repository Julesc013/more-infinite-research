local defaults = require("defaults")

local R = {}

local function startup_setting(name)
  local setting = settings and settings.startup and settings.startup[name]
  if setting then return setting.value end
  return nil
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

function R.stream_default_enabled(key, spec)
  return lookup_default("stream", key, "enabled", spec, true) == true
end

function R.base_default_enabled(key, spec)
  return lookup_default("base", key, "enabled", spec, true) == true
end

function R.stream_enabled(key, spec)
  local fallback = R.stream_default_enabled(key, spec)
  local setting = startup_setting("ips-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

function R.base_enabled(key, spec)
  local fallback = R.base_default_enabled(key, spec)
  local setting = startup_setting("mir-enable-" .. key)
  if setting ~= nil then return setting == true end
  return fallback
end

return R
