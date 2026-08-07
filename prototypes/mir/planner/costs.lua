local C = require("prototypes.mir.streams.registry")
local defaults = require("prototypes.mir.settings.defaults")
local settings_resolver = require("prototypes.mir.settings.resolver")
local effective_settings = require("prototypes.mir.settings.effective")
local cost_contract = require("prototypes.mir.settings.cost_contract")
local research_cost_model = require("prototypes.mir.domain.research_cost.model")

local M = {}

local function startup_setting(name)
  return effective_settings.get(name)
end

local function ensure_minimum(value, fallback, minimum)
  minimum = minimum or 0
  if type(value) ~= "number" then return fallback end
  if value < minimum then return fallback end
  return value
end

local function lookup_default(key, field, spec, fallback)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults[field] ~= nil then return stream_defaults[field] end
  if spec and spec[field] ~= nil then return spec[field] end
  local shared_defaults = defaults.shared or {}
  if shared_defaults[field] ~= nil then return shared_defaults[field] end
  return fallback
end

local function coerce_max_level(value)
  if value == nil then return nil end
  if value == "infinite" then return "infinite" end
  if type(value) == "number" then
    if value <= 0 then return "infinite" end
    return math.floor(value)
  end
  if type(value) == "string" then
    local num = tonumber(value)
    if not num or num <= 0 then return "infinite" end
    return math.floor(num)
  end
  return "infinite"
end

function M.enabled_for(key, spec)
  return settings_resolver.stream_enabled(key, spec)
end

function M.base_cost_for(key, spec)
  local default = lookup_default(key, "base_cost", spec, C.shared.base_cost)
  local value = startup_setting("ips-cost-base-" .. key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.base_cost, 1)
end

function M.growth_factor_for(key, spec)
  local default = lookup_default(key, "growth_factor", spec, C.shared.growth_factor)
  local value = startup_setting("ips-cost-growth-" .. key)
  if value ~= nil then return ensure_minimum(value, default, 1) end
  return ensure_minimum(default, C.shared.growth_factor, 1)
end

function M.linear_increment_for(key, spec)
  local default = lookup_default(key, "linear_increment", spec, 0)
  local value = startup_setting(cost_contract.stream_name("linear_increment", key))
  if value ~= nil then return ensure_minimum(value, default, 0) end
  return ensure_minimum(default, 0, 0)
end

function M.model_for(key, spec, anchor_level)
  return research_cost_model.new({
    anchor_level = anchor_level or 1,
    base_cost = M.base_cost_for(key, spec),
    linear_increment = M.linear_increment_for(key, spec),
    growth_factor = M.growth_factor_for(key, spec),
    provenance = {
      base_cost = cost_contract.stream_name("base_cost", key),
      linear_increment = cost_contract.stream_name("linear_increment", key),
      growth_factor = cost_contract.stream_name("growth_factor", key),
      anchor_level = "technology-first-level"
    }
  })
end

function M.research_time_for(key, spec)
  local default = ensure_minimum(lookup_default(key, "research_time", spec, C.shared.research_time), C.shared.research_time, 1)
  local value = startup_setting("ips-research-time-" .. key)
  if value ~= nil then
    if value <= 0 then return default end
    return ensure_minimum(value, default, 1)
  end
  return default
end

function M.max_level_for(key, spec)
  local setting_value = startup_setting("ips-max-level-" .. key)
  if setting_value ~= nil then
    if setting_value <= 0 then return "infinite" end
    return math.floor(setting_value)
  end
  local from_spec = coerce_max_level(lookup_default(key, "max_level", spec, nil))
  if from_spec ~= nil then return from_spec end
  return "infinite"
end

return M
