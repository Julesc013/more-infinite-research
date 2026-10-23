-- Small settings-stage authority for the MIR5 gear and native-tail slice.
-- Profile transport is deliberately generic and lives in research.settings_profile.
local profile_codec = require("research.settings_profile")

local M = {}

M.import_setting_name = "mir-settings-profile-import"

local gear_key = "research_gears"
local fields = {
  {key = "enabled", name = "ips-enable-", type = "bool-setting", default_value = true},
  {key = "base_cost", name = "ips-cost-base-", type = "int-setting", default_value = 8000, minimum_value = 1, maximum_value = 2147483647},
  {key = "linear_increment", name = "ips-cost-linear-increment-", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  -- Factorio's prototype has no maximum. MIRSET1 rejects values above 1000.
  {key = "growth_factor", name = "ips-cost-growth-", type = "double-setting", default_value = 2, minimum_value = 1, profile_maximum_value = 1000},
  {key = "max_level", name = "ips-max-level-", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  {key = "research_time", name = "ips-research-time-", type = "int-setting", default_value = 60, minimum_value = 0, maximum_value = 2147483647},
  {key = "effect_percent", name = "ips-effect-per-level-", type = "double-setting", default_value = 10, minimum_value = 0.01, maximum_value = 1000000}
}

local native_fields = {
  {key = "worker_robots_speed_max_level", name = "mir-max-level-worker-robots-speed", type = "int-setting", default_value = 0, minimum_value = 0, maximum_value = 2147483647},
  {key = "passive_repair_enabled", name = "mir-enable-passive-repair", type = "bool-setting", default_value = false}
}

local function copy_spec(spec)
  local out = {}
  for name, value in pairs(spec) do out[name] = value end
  return out
end

local declarations, declaration_by_name = {}, {}
for _, field in ipairs(fields) do
  local spec = copy_spec(field)
  spec.name = spec.name .. gear_key
  declarations[#declarations + 1] = spec
  declaration_by_name[spec.name] = spec
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
  for index, spec in ipairs(declarations) do
    local name, description, order
    if index <= #fields then
      local locale_key = fields[index].name .. "stream"
      name = {"mod-setting-name." .. locale_key, {"technology-name.more-infinite-research.research_gears"}}
      description = {"mod-setting-description." .. locale_key, {"technology-name.more-infinite-research.research_gears"}}
      order = "b-100-iron-gear-wheel-productivity-stream-research_gears-" .. (index - 1)
    else
      name = {"mod-setting-name." .. spec.name}
      description = {"mod-setting-description." .. spec.name}
      order = spec.name == "mir-max-level-worker-robots-speed" and "c-200-worker-robots-speed-cap" or "c-210-passive-repair"
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
  for _, spec in ipairs(declarations) do values[spec.key] = effective[spec.name] end
  -- Consumer normalization only: export retains a literal configured zero.
  if values.research_time == 0 then values.research_time = 60 end
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
