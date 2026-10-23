-- Small settings-stage authority for the MIR5 gear and native-tail slice.
-- Profile transport is deliberately generic and lives in research.settings_profile.
local profile_codec = require("research.settings_profile")

local M = {}

M.import_setting_name = "mir-settings-profile-import"

local fields = {
  {key = "enabled", name = "ips-enable-", type = "bool-setting"},
  {key = "base_cost", name = "ips-cost-base-", type = "int-setting", minimum_value = 1, maximum_value = 2147483647},
  {key = "linear_increment", name = "ips-cost-linear-increment-", type = "int-setting", minimum_value = 0, maximum_value = 2147483647},
  -- Factorio's prototype has no maximum. MIRSET1 rejects values above 1000.
  {key = "growth_factor", name = "ips-cost-growth-", type = "double-setting", minimum_value = 1, profile_maximum_value = 1000},
  {key = "max_level", name = "ips-max-level-", type = "int-setting", minimum_value = 0, maximum_value = 2147483647},
  {key = "research_time", name = "ips-research-time-", type = "int-setting", minimum_value = 0, maximum_value = 2147483647},
  {key = "effect_percent", name = "ips-effect-per-level-", type = "double-setting", minimum_value = 0.01, maximum_value = 1000000}
}

local streams = {{
  key = "research_gears", value_key = "gear",
  technology_locale = "technology-name.more-infinite-research.research_gears",
  order_prefix = "b-100-iron-gear-wheel-productivity-stream-research_gears-",
  defaults = {enabled = true, base_cost = 8000, linear_increment = 0,
    growth_factor = 2, max_level = 0, research_time = 60, effect_percent = 10}
}}

-- The selected module contains the two non-base setting descriptors. A
-- base-only data/control stage does not construct or import those rows.
-- Settings is shared by data and control stages. Data exposes `mods`; the
-- control-stage authority is `script.active_mods`. Keep the inactive module
-- unrequired in both environments.
local active_mods = script and script.active_mods or mods or {}
local space_age_active = type(active_mods) == "table" and active_mods["space-age"] ~= nil
if space_age_active then
  local scripted = require("research.settings.space_age_scripted")
  for _, stream in ipairs(scripted.streams) do streams[#streams + 1] = stream end
end

local native_fields = {
  {key = "worker_robots_speed_max_level", name = "mir-max-level-worker-robots-speed", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  {key = "passive_repair_enabled", name = "mir-enable-passive-repair", type = "bool-setting", default_value = false},
  {key = "unrestricted_modules", name = "mir-unrestricted-modules", type = "bool-setting", default_value = false}
}

local function copy_spec(spec)
  local out = {}
  for name, value in pairs(spec) do out[name] = value end
  return out
end

local declarations, declaration_by_name = {}, {}
for _, stream in ipairs(streams) do
  for index, field in ipairs(fields) do
    local spec = copy_spec(field)
    spec.name = spec.name .. stream.key
    spec.default_value = stream.defaults[spec.key]
    spec.stream = stream
    spec.field_index = index
    declarations[#declarations + 1] = spec
    declaration_by_name[spec.name] = spec
  end
end
for _, field in ipairs(native_fields) do
  local spec = copy_spec(field)
  declarations[#declarations + 1] = spec
  declaration_by_name[spec.name] = spec
end

local function spec_for(name) return declaration_by_name[name] end

local function finite_number(value)
  return type(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function valid(spec, value, imported)
  if spec.type == "bool-setting" then return type(value) == "boolean" end
  if not finite_number(value) then return false end
  if spec.type == "int-setting" and value ~= math.floor(value) then return false end
  if value < spec.minimum_value then return false end
  local maximum = imported and spec.profile_maximum_value or spec.maximum_value
  return maximum == nil or value <= maximum
end

function M.prototypes()
  local out = {{
    type = "string-setting", name = M.import_setting_name, setting_type = "startup",
    default_value = "", allow_blank = true, order = "a-7-010",
    localised_name = {"mod-setting-name.mir-settings-profile-import"},
    localised_description = {"mod-setting-description.mir-settings-profile-import"}
  }}
  for _, spec in ipairs(declarations) do
    local name, description, order
    if spec.stream then
      local locale_key = fields[spec.field_index].name .. "stream"
      name = {"mod-setting-name." .. locale_key, {spec.stream.technology_locale}}
      local generic_description = {"mod-setting-description." .. locale_key, {spec.stream.technology_locale}}
      if spec.stream.description_note then
        description = {"", generic_description, "\n\n", {spec.stream.description_note}}
      elseif spec.stream.enable_note and spec.field_index == 1 then
        description = {"", generic_description, "\n\n", {spec.stream.enable_note}}
      else
        description = generic_description
      end
      order = spec.stream.order_prefix .. (spec.field_index - 1)
    else
      name = {"mod-setting-name." .. spec.name}
      description = {"mod-setting-description." .. spec.name}
      if spec.name == "mir-max-level-worker-robots-speed" then
        order = "c-200-worker-robots-speed-cap"
      elseif spec.name == "mir-enable-passive-repair" then
        order = "c-210-passive-repair"
      else
        order = "c-220-unrestricted-modules"
      end
    end
    out[#out + 1] = {
      type = spec.type, name = spec.name, setting_type = "startup",
      default_value = spec.default_value, minimum_value = spec.minimum_value,
      maximum_value = spec.maximum_value,
      order = order, localised_name = name, localised_description = description
    }
  end
  return out
end

function M.registered_names()
  local out = {}
  for _, spec in ipairs(declarations) do out[#out + 1] = spec.name end
  return out
end

function M.spec(name)
  local spec = spec_for(name)
  return spec and copy_spec(spec) or nil
end

function M.default_value(name)
  local spec = spec_for(name)
  if spec then return spec.default_value end
  return nil
end

function M.validate_value(name, value)
  if name == M.import_setting_name then return false, "profile import setting is not importable" end
  local spec = spec_for(name)
  if not spec then return false, "unknown setting" end
  if valid(spec, value, true) then return true end
  if type(value) ~= (spec.type == "bool-setting" and "boolean" or "number") then return false, "wrong type" end
  if not finite_number(value) and spec.type ~= "bool-setting" then return false, "not finite" end
  if spec.type == "int-setting" and value ~= math.floor(value) then return false, "not an integer" end
  if value < spec.minimum_value then return false, "below minimum" end
  return false, "above maximum"
end

function M.is_default_value(name, value)
  local spec = spec_for(name)
  return spec ~= nil and spec.default_value == value
end

local function raw_value(startup, name, default_value)
  local setting = startup and startup[name]
  if setting and setting.value ~= nil then return setting.value end
  return default_value
end

local function decoded_import(startup, helpers, report)
  local text = raw_value(startup, M.import_setting_name, "")
  if text == nil or text == "" then return nil end
  local ok, profile = pcall(profile_codec.decode, text, helpers)
  if ok and profile then return profile.settings end
  if report then report("[more-infinite-research] Ignoring invalid MIR settings profile import") end
  return nil
end

-- Returns native-name keyed values before any consumer-specific normalization.
function M.effective_values(startup, helpers, report)
  local imported = decoded_import(startup, helpers, report)
  local out = {}
  for _, spec in ipairs(declarations) do
    local value = raw_value(startup, spec.name, spec.default_value)
    if imported and startup and startup[spec.name] and imported[spec.name] ~= nil
      and valid(spec, imported[spec.name], true) then
      value = imported[spec.name]
    end
    assert(valid(spec, value, false), "MIR invalid effective setting: " .. spec.name)
    out[spec.name] = value
  end
  return out
end

function M.resolve(startup, helpers, report)
  local effective = M.effective_values(startup, helpers, report)
  local values = {}
  for _, stream in ipairs(streams) do
    local stream_values = {}
    for _, field in ipairs(fields) do
      local value = effective[field.name .. stream.key]
      -- Consumer normalization only: export retains a literal configured zero.
      if field.key == "research_time" and value == 0 then value = stream.defaults.research_time end
      stream_values[field.key] = value
    end
    if stream.key == "research_gears" then
      for key, value in pairs(stream_values) do values[key] = value end
    else
      values[stream.value_key] = stream_values
    end
  end
  for _, spec in ipairs(native_fields) do values[spec.key] = effective[spec.name] end
  return values
end

function M.profile_status(profile, startup)
  local status = {recognized = 0, unknown = 0, invalid = 0}
  for name, value in pairs((profile and profile.settings) or {}) do
    if name == M.import_setting_name or not spec_for(name) or not (startup and startup[name]) then
      status.unknown = status.unknown + 1
    elseif M.validate_value(name, value) then
      status.recognized = status.recognized + 1
    else
      status.invalid = status.invalid + 1
    end
  end
  return status
end

return M
