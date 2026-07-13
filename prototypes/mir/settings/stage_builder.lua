local C = require("prototypes.mir.streams.registry")
local streams = C.snapshot()
local defaults = require("prototypes.mir.settings.defaults")
local settings_catalog = require("prototypes.mir.settings.catalog")
local settings_adapter = require("prototypes.mir.settings.stage_adapter")
local setting_order = require("prototypes.mir.settings.order")

local settings_data = {}
local settings_context = settings_adapter.context()
local base_defaults = defaults.base_extensions or {}

local function lookup_default(key, field, stream, fallback)
  local stream_defaults = defaults.streams and defaults.streams[key]
  if stream_defaults and stream_defaults[field] ~= nil then return stream_defaults[field] end
  if stream and stream[field] ~= nil then return stream[field] end
  local shared_defaults = defaults.shared or {}
  if shared_defaults[field] ~= nil then return shared_defaults[field] end
  return fallback
end

local function default_enabled(key, stream)
  local value = lookup_default(key, "enabled", stream, true)
  return not not value
end

local function append_note(description, note)
  if not note then return description end
  return {"", description, "\n\n", note}
end

local function add_technology_setting(group, setting)
  table.insert(settings_data, settings_adapter.apply(setting, group and group.ui_visibility))
end

local function copy_spec(spec)
  local out = {}
  for key, value in pairs(spec) do out[key] = value end
  return out
end

local function decorate_stream_setting(spec, tech_locale, order_prefix)
  local out = copy_spec(spec)
  out.setting_type = "startup"
  if string.find(out.name, "^ips%-enable%-") then
    out.order = order_prefix .. "-0"
    out.localised_name = {"mod-setting-name.ips-enable-stream", tech_locale}
    out.localised_description = append_note({"mod-setting-description.ips-enable-stream", tech_locale}, nil)
  elseif string.find(out.name, "^ips%-cost%-base%-") then
    out.order = order_prefix .. "-1"
    out.localised_name = {"mod-setting-name.ips-cost-base-stream", tech_locale}
    out.localised_description = {"mod-setting-description.ips-cost-base-stream", tech_locale}
  elseif string.find(out.name, "^ips%-cost%-growth%-") then
    out.order = order_prefix .. "-2"
    out.localised_name = {"mod-setting-name.ips-cost-growth-stream", tech_locale}
    out.localised_description = {"mod-setting-description.ips-cost-growth-stream", tech_locale}
  elseif string.find(out.name, "^ips%-max%-level%-") then
    out.order = order_prefix .. "-3"
    out.localised_name = {"mod-setting-name.ips-max-level-stream", tech_locale}
    out.localised_description = {"mod-setting-description.ips-max-level-stream", tech_locale}
  elseif string.find(out.name, "^ips%-research%-time%-") then
    out.order = order_prefix .. "-4"
    out.localised_name = {"mod-setting-name.ips-research-time-stream", tech_locale}
    out.localised_description = {"mod-setting-description.ips-research-time-stream", tech_locale}
  elseif string.find(out.name, "^ips%-effect%-per%-level%-") then
    out.order = order_prefix .. "-5"
    out.localised_name = {"mod-setting-name.ips-effect-per-level-stream", tech_locale}
    out.localised_description = {"mod-setting-description.ips-effect-per-level-stream", tech_locale}
  else
    error("Unknown generated stream setting: " .. tostring(out.name))
  end
  return out
end

local function decorate_base_setting(spec, tech_locale, order_prefix, settings_note)
  local out = copy_spec(spec)
  out.setting_type = "startup"
  if string.find(out.name, "^mir%-enable%-") then
    out.order = order_prefix .. "-0"
    out.localised_name = {"mod-setting-name.mir-enable-base-tech", tech_locale}
    out.localised_description = append_note({"mod-setting-description.mir-enable-base-tech", tech_locale}, settings_note)
  elseif string.find(out.name, "^mir%-cost%-base%-") then
    out.order = order_prefix .. "-1"
    out.localised_name = {"mod-setting-name.mir-cost-base", tech_locale}
    out.localised_description = {"mod-setting-description.mir-cost-base", tech_locale}
  elseif string.find(out.name, "^mir%-cost%-growth%-") then
    out.order = order_prefix .. "-2"
    out.localised_name = {"mod-setting-name.mir-cost-growth", tech_locale}
    out.localised_description = {"mod-setting-description.mir-cost-growth", tech_locale}
  elseif string.find(out.name, "^mir%-max%-level%-") then
    out.order = order_prefix .. "-3"
    out.localised_name = {"mod-setting-name.mir-max-level", tech_locale}
    out.localised_description = {"mod-setting-description.mir-max-level", tech_locale}
  elseif string.find(out.name, "^mir%-research%-time%-") then
    out.order = order_prefix .. "-4"
    out.localised_name = {"mod-setting-name.mir-research-time", tech_locale}
    out.localised_description = {"mod-setting-description.mir-research-time", tech_locale}
  elseif string.find(out.name, "^mir%-effect%-per%-level%-") then
    out.order = order_prefix .. "-5"
    out.localised_name = {"mod-setting-name.mir-effect-per-level", tech_locale}
    out.localised_description = {"mod-setting-description.mir-effect-per-level", tech_locale}
  else
    error("Unknown base extension setting: " .. tostring(out.name))
  end
  return out
end

for _, setting in ipairs(settings_catalog.global_setting_prototypes()) do
  table.insert(settings_data, setting)
end

local base_extension_specs = settings_catalog.base_extension_specs()

local function order_slug(value)
  local out = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if out == "" then return "zzz" end
  return out
end

local function group_attention_rank(group)
  if not group.enabled then return "000" end
  if group.settings_priority == "top" then return "050" end
  return "100"
end

local function group_order_prefix(group)
  local bucket = group_attention_rank(group)
  return setting_order.technology(bucket, order_slug(group.sort_name), group.kind, group.key)
end

local technology_setting_groups = {}

for key, stream in pairs(streams) do
  table.insert(technology_setting_groups, {
    kind = "stream",
    key = key,
    stream = stream,
    sort_name = stream.descriptor.ui.sort_name,
    enabled = default_enabled(key, stream),
    settings_priority = lookup_default(key, "settings_priority", stream, nil),
    ui_visibility = settings_adapter.visibility_for_stream(stream, settings_context)
  })
end

for _, spec in ipairs(base_extension_specs) do
  local defaults_spec = base_defaults[spec.key] or {}
  local enabled = defaults_spec.enabled
  if enabled == nil then enabled = true end
  table.insert(technology_setting_groups, {
    kind = "base",
    key = spec.key,
    spec = spec,
    defaults_spec = defaults_spec,
    sort_name = spec.sort_name or spec.key,
    enabled = enabled,
    settings_priority = spec.settings_priority or defaults_spec.settings_priority
  })
end

table.sort(technology_setting_groups, function(a, b)
  local rank_a = group_attention_rank(a)
  local rank_b = group_attention_rank(b)
  if rank_a ~= rank_b then return rank_a < rank_b end
  local sort_a = order_slug(a.sort_name)
  local sort_b = order_slug(b.sort_name)
  if sort_a == sort_b then
    if a.kind == b.kind then return a.key < b.key end
    return a.kind < b.kind
  end
  return sort_a < sort_b
end)

for _, group in ipairs(technology_setting_groups) do
  local order_prefix = group_order_prefix(group)

  if group.kind == "stream" then
    local key = group.key
    local stream = group.stream
    local tech_locale = stream.localised_name or {"technology-name.more-infinite-research."..key}
    local settings_note = lookup_default(key, "settings_note", stream, nil)
    for _, spec in ipairs(settings_catalog.stream_setting_specs(key, stream)) do
      local setting = decorate_stream_setting(spec, tech_locale, order_prefix)
      setting.localised_description = append_note(setting.localised_description, settings_note)
      add_technology_setting(group, setting)
    end
  else
    local spec = group.spec
    local defaults_spec = group.defaults_spec
    local locale_key = defaults_spec.locale_key or defaults_spec.chain_key or spec.locale_key or spec.key
    local locale = {"technology-name."..locale_key}
    for _, setting_spec in ipairs(settings_catalog.base_extension_setting_specs(spec.key)) do
      add_technology_setting(group, decorate_base_setting(setting_spec, locale, order_prefix, defaults_spec.settings_note))
    end
  end
end

data:extend(settings_data)
