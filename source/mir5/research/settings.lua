-- Startup settings for explicitly authored MIR research families. Profile
-- transport remains generic in research.settings_profile; this module names
-- every published setting and resolves it once for data or runtime consumers.
local profile_codec = require("research.settings_profile")
local modern_catalogue = require("compatibility.modern_catalogue")
local historical = require("research.historical_settings")

local M = {}
M.import_setting_name = "mir-settings-profile-import"

local active_mods = script and script.active_mods or mods or {}
local space_age_active = type(active_mods) == "table" and active_mods["space-age"] ~= nil
local k2so_active = modern_catalogue.is_k2so(active_mods)
local bob_angel_active = modern_catalogue.is_bob_angel(active_mods)
local bob_tech_active = require("compatibility.bob_tech_profile").applies(active_mods)
local atan_active = (active_mods["atan-air-scrubbing"] or active_mods["atan-ash"])
  and require("compatibility.atan_profile").select(active_mods, require("platform.target")) ~= nil
local native_owner_families = {}
for _, owner in ipairs(modern_catalogue.native_owners(active_mods)) do native_owner_families[owner.family] = true end

local normal_fields = {
  {key="enabled", prefix="ips-enable-", type="bool-setting"},
  {key="base_cost", prefix="ips-cost-base-", type="int-setting", minimum_value=1, maximum_value=2147483647},
  {key="linear_increment", prefix="ips-cost-linear-increment-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="growth_factor", prefix="ips-cost-growth-", type="double-setting", minimum_value=1, profile_maximum_value=1000},
  {key="max_level", prefix="ips-max-level-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="research_time", prefix="ips-research-time-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="effect_percent", prefix="ips-effect-per-level-", type="double-setting", minimum_value=0.01, maximum_value=1000000}
}

-- Stable MIR4 continuation IDs retain their own prefix, zero sentinels and
-- localized setting grammar. A zero base/growth/time means inherit the named
-- pre-continuation chain, which research.modern resolves without discovery.
local native_fields = {
  {key="enabled", prefix="mir-enable-", type="bool-setting"},
  {key="base_cost", prefix="mir-cost-base-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="linear_increment", prefix="mir-cost-linear-increment-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="growth_factor", prefix="mir-cost-growth-", type="double-setting", minimum_value=0, profile_maximum_value=1000},
  {key="max_level", prefix="mir-max-level-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="research_time", prefix="mir-research-time-", type="int-setting", minimum_value=0, maximum_value=2147483647},
  {key="effect_percent", prefix="mir-effect-per-level-", type="double-setting", minimum_value=0.01, maximum_value=1000000}
}

local streams = {}
for _, historical_stream in ipairs(historical.streams) do
  if modern_catalogue.supports_family(historical_stream.key) then
    local fields, defaults = {}, historical_stream.defaults
    local field_overrides = historical_stream.field_overrides
    if space_age_active and historical_stream.space_age_visible then
      field_overrides = historical_stream.space_age_field_overrides or {}
    end
    if k2so_active and historical_stream.k2so_defaults then
      defaults = {}
      for key, value in pairs(historical_stream.defaults) do defaults[key] = value end
      for key, value in pairs(historical_stream.k2so_defaults) do defaults[key] = value end
    end
    for index, base in ipairs(normal_fields) do
      local field, override = {}, field_overrides[base.key] or {}
      for key, value in pairs(base) do field[key] = value end
      for key, value in pairs(override) do field[key] = value end
      -- Published K2SO omits the hidden field instead of declaring false.
      if k2so_active and historical_stream.k2so_visible then field.hidden = nil end
      if bob_angel_active and require("compatibility.bob_angel_profile").setting_visible(historical_stream.key) then
        field.hidden = nil
      end
      if bob_tech_active and require("compatibility.bob_tech_profile").setting_visible(historical_stream.key) then
        field.hidden = nil
      end
      if atan_active and (historical_stream.key == "research_air_scrubbing_clean_filter"
        or historical_stream.key == "research_ash_separation") then field.hidden = nil end
      fields[index] = field
    end
    streams[#streams + 1] = {
      key=historical_stream.key, technology_locale=historical_stream.locale,
      order_prefix=historical_stream.order_prefix, fields=fields, defaults=defaults,
      description_note=historical_stream.description_note, enabled_note=historical_stream.enabled_note,
      native_owner=native_owner_families[historical_stream.key] == true
    }
  end
end

-- Stable MIR4 continuation IDs retain their own prefix, zero sentinels and
-- localized setting grammar. Settings do not need a Space Age mapping body:
-- their defaults are target-invariant, so this requests only the base rows.
for _, continuation in ipairs(modern_catalogue.continuations({})) do
  local fields = {}
  for index, field in ipairs(native_fields) do
    local copied = {}
    for key, value in pairs(field) do copied[key] = value end
    if field.key == "effect_percent" and (continuation.key == "inserter_capacity_bonus" or continuation.key == "worker_robots_storage") then
      copied.type, copied.minimum_value = "int-setting", 1
    end
    fields[index] = copied
  end
  streams[#streams + 1] = {
    key=continuation.family, setting_key=continuation.setting_key, technology_locale=continuation.localised_name,
    order_prefix=continuation.setting_order, fields=fields, defaults=continuation.defaults,
    native_continuation=true, continuation_id=continuation.id, inherit_research_time=true,
    setting_notes=continuation.setting_notes
  }
end

-- Other historic startup controls are individually authored options. They
-- stay declared for stable profile/settings identity but do not activate a
-- retired compiler, planner, or integration body.
local native_fields_static = historical.options

local function copy_spec(spec, seen)
  if type(spec) ~= "table" then return spec end
  seen = seen or {}
  if seen[spec] then error("MIR settings descriptor contains a cycle", 3) end
  seen[spec] = true
  local out = {}
  for name, value in pairs(spec) do out[name] = copy_spec(value, seen) end
  seen[spec] = nil
  return out
end

local function locale_argument(value)
  if type(value) == "string" then return {value} end
  return copy_spec(value)
end

local declarations, declaration_by_name = {}, {}
for _, stream in ipairs(streams) do
  local setting_key = stream.setting_key or stream.key
  for index, field in ipairs(stream.fields) do
    local spec = copy_spec(field)
    spec.name = spec.prefix .. setting_key
    spec.default_value, spec.stream, spec.field_index = stream.defaults[spec.key], stream, index
    declarations[#declarations + 1], declaration_by_name[spec.name] = spec, spec
  end
end
for _, field in ipairs(native_fields_static) do
  local spec = copy_spec(field)
  declarations[#declarations + 1], declaration_by_name[spec.name] = spec, spec
end

local function spec_for(name) return declaration_by_name[name] end
local function finite_number(value) return type(value) == "number" and value == value and value < math.huge and value > -math.huge end
local function valid(spec, value, imported)
  if spec.type == "bool-setting" then return type(value) == "boolean" end
  if spec.type == "string-setting" then
    if type(value) ~= "string" then return false end
    if type(spec.allowed_values) ~= "table" then return true end
    for _, allowed in ipairs(spec.allowed_values) do if value == allowed then return true end end
    return false
  end
  if not finite_number(value) then return false end
  if spec.type == "int-setting" and value ~= math.floor(value) then return false end
  if spec.minimum_value ~= nil and value < spec.minimum_value then return false end
  local maximum = imported and spec.profile_maximum_value or spec.maximum_value
  return maximum == nil or value <= maximum
end

local native_locale = {
  enabled="mir-enable-base-tech", base_cost="mir-cost-base", linear_increment="mir-cost-linear-increment",
  growth_factor="mir-cost-growth", max_level="mir-max-level", research_time="mir-research-time", effect_percent="mir-effect-per-level"
}

function M.prototypes()
  local out = {{type="string-setting", name=M.import_setting_name, setting_type="startup", default_value="", allow_blank=true,
    order="a-7-010", localised_name={"mod-setting-name.mir-settings-profile-import"}, localised_description={"mod-setting-description.mir-settings-profile-import"}}}
  for _, spec in ipairs(declarations) do
    local name, description, order
    if spec.stream then
      local stream = spec.stream
      local field = stream.fields[spec.field_index]
      local technology = locale_argument(stream.technology_locale)
      if stream.native_continuation then
        local locale = native_locale[field.key]
        name = {"mod-setting-name." .. locale, technology}
        description = {"mod-setting-description." .. locale, technology}
        local note = stream.setting_notes and stream.setting_notes[field.key]
        if note then description = {"", description, "\n\n", copy_spec(note)} end
      else
        local locale = field.prefix .. "stream"
        name = {"mod-setting-name." .. locale, technology}
        local generic_description = {"mod-setting-description." .. locale, technology}
        local note = stream.description_note
        if spec.field_index == 1 and stream.enabled_note then note = stream.enabled_note end
        if note then description = {"", generic_description, "\n\n", copy_spec(note)}
        elseif stream.enable_note and spec.field_index == 1 then description = {"", generic_description, "\n\n", {stream.enable_note}}
        else description = generic_description end
      end
      order = stream.order_prefix .. (spec.field_index - 1)
      out[#out + 1] = {type=spec.type,name=spec.name,setting_type="startup",default_value=spec.default_value,
        minimum_value=spec.minimum_value,maximum_value=spec.maximum_value,allowed_values=spec.allowed_values,
        hidden=spec.hidden,allow_blank=spec.allow_blank,order=order,localised_name=name,localised_description=description}
    else
      -- Historical standalone controls retain their exact bounded identity;
      -- return a deep copy so a consumer cannot mutate declaration state.
      local option = copy_spec(spec)
      option.setting_type = option.setting_type or "startup"
      out[#out + 1] = option
    end
  end
  return out
end

function M.registered_names()
  local out = {}
  for _, spec in ipairs(declarations) do out[#out + 1] = spec.name end
  return out
end
function M.spec(name) local spec=spec_for(name); return spec and copy_spec(spec) or nil end
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
  local expected = spec.type == "bool-setting" and "boolean" or (spec.type == "string-setting" and "string" or "number")
  if type(value) ~= expected then return false, "wrong type" end
  if spec.type == "string-setting" then return false, "not an allowed value" end
  if not finite_number(value) then return false, "not finite" end
  if spec.type == "int-setting" and value ~= math.floor(value) then return false, "not an integer" end
  if spec.minimum_value ~= nil and value < spec.minimum_value then return false, "below minimum" end
  return false, "above maximum"
end
function M.is_default_value(name, value) local spec=spec_for(name); return spec ~= nil and spec.default_value == value end

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

function M.effective_values(startup, helpers, report)
  local imported, out = decoded_import(startup, helpers, report), {}
  for _, spec in ipairs(declarations) do
    local value = raw_value(startup, spec.name, spec.default_value)
    if imported and startup and startup[spec.name] and imported[spec.name] ~= nil and valid(spec, imported[spec.name], true) then value = imported[spec.name] end
    assert(valid(spec, value, false), "MIR invalid effective setting: " .. spec.name)
    out[spec.name] = value
  end
  return out
end

function M.resolve(startup, helpers, report)
  local effective, values = M.effective_values(startup, helpers, report), {streams={}, native_continuations={}}
  for _, stream in ipairs(streams) do
    local stream_values, setting_key = {}, stream.setting_key or stream.key
    local configured = {}
    for _, field in ipairs(stream.fields) do
      local value = effective[field.prefix .. setting_key]
      configured[field.key] = value ~= stream.defaults[field.key]
      if field.key == "research_time" and value == 0 and not stream.inherit_research_time
          and not stream.native_owner then
        value = stream.defaults.research_time
      end
      stream_values[field.key] = value
    end
    stream_values.configured = configured
    values.streams[stream.key] = stream_values
    if stream.value_key then values[stream.value_key] = stream_values end
    if stream.native_continuation then values.native_continuations[stream.key] = stream_values end
    if stream.key == "research_gears" then for key, value in pairs(stream_values) do values[key] = value end end
    if stream.key == "research_agricultural_growth_speed" then values.agricultural_growth_speed = stream_values end
    if stream.key == "research_spoilage_preservation" then values.spoilage_preservation = stream_values end
  end
  if k2so_active then
    values.streams.research_material_imersite__continuation = values.streams.research_material_imersite
  end
  values.options = {}
  local aliases = { ["mir-max-level-worker-robots-speed"]="worker_robots_speed_max_level",
    ["mir-enable-passive-repair"]="passive_repair_enabled", ["mir-unrestricted-modules"]="unrestricted_modules" }
  for _, spec in ipairs(native_fields_static) do
    local value = effective[spec.name]
    values.options[spec.name] = value
    if aliases[spec.name] then values[aliases[spec.name]] = value end
  end
  return values
end

function M.profile_status(profile, startup)
  local status = {recognized=0,unknown=0,invalid=0}
  for name, value in pairs((profile and profile.settings) or {}) do
    if name == M.import_setting_name or not spec_for(name) or not (startup and startup[name]) then status.unknown = status.unknown + 1
    elseif M.validate_value(name, value) then status.recognized = status.recognized + 1
    else status.invalid = status.invalid + 1 end
  end
  return status
end

return M
