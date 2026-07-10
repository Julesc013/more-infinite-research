local C = require("prototypes.mir.streams.registry")
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

local function default_base_cost(key, stream)
  return lookup_default(key, "base_cost", stream, C.shared.base_cost)
end

local function default_growth_factor(key, stream)
  return lookup_default(key, "growth_factor", stream, C.shared.growth_factor)
end

local function default_max_level_setting(key, stream)
  local ml = lookup_default(key, "max_level", stream, 0)
  if ml == nil or ml == "infinite" then return 0 end
  local num = tonumber(ml)
  if not num or num <= 0 then return 0 end
  return math.floor(num)
end

local function default_research_time_setting(key, stream)
  local value = lookup_default(key, "research_time", stream, C.shared.research_time)
  if not value or value <= 0 then value = C.shared.research_time end
  return math.floor(value + 0.5)
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

local stream_sort_names = {
  research_advanced_circuit = "Advanced circuit productivity",
  research_agricultural_growth_speed = "Agricultural growth speed",
  research_air_scrubbing_clean_filter = "Air Scrubbing clean-filter productivity",
  research_armor_components = "Armor component productivity",
  research_ash_separation = "Ash separation productivity",
  research_bacteria_cultivation = "Bacteria cultivation productivity",
  research_batteries = "Battery productivity",
  research_belts = "Transport belt productivity",
  research_bioflux = "Bioflux productivity",
  research_breeding = "Breeding productivity",
  research_bullets = "Bullet productivity",
  research_cannon_shooting_speed = "Cannon shooting speed",
  research_cargo_bay_unloading_distance = "Cargo bay unloading distance",
  research_cargo_landing_pad_count = "Cargo landing pad count",
  research_artificial_soil = "Artificial soil productivity",
  research_carbon = "Carbon productivity",
  research_carbon_fiber = "Carbon fiber productivity",
  research_character_crafting_speed = "Character crafting speed",
  research_character_mining_speed = "Character mining speed",
  research_character_reach = "Character reach bonus",
  research_character_walking_speed = "Character walking speed",
  research_concrete = "Concrete productivity",
  research_copper = "Copper plate productivity",
  research_copper_cable = "Copper cable productivity",
  research_electric_energy = "Electric energy productivity",
  research_electric_engine = "Electric engine unit productivity",
  research_electric_shooting_speed = "Electric shooting speed",
  research_electronic_circuit = "Electronic circuit productivity",
  research_engine = "Engine unit productivity",
  research_explosives = "Explosives productivity",
  research_flamethrower_shooting_speed = "Flamethrower shooting speed",
  research_flying_robot_frame = "Flying robot frame productivity",
  research_furnace = "Furnace productivity",
  research_gears = "Iron gear wheel productivity",
  research_grenades = "Grenade productivity",
  research_heavy_ammo = "Cannon shell productivity",
  research_holmium = "Holmium productivity",
  research_ice = "Ice productivity",
  research_inserters = "Inserter productivity",
  research_inventory_capacity = "Character inventory slots",
  research_iron = "Iron plate productivity",
  research_iron_sticks = "Iron stick productivity",
  research_lab_productivity = "Research productivity",
  research_landfill = "Landfill productivity",
  research_lithium = "Lithium productivity",
  research_low_density_structure = "Low density structure productivity",
  research_mining_drill = "Mining drill productivity",
  research_modules = "Module productivity",
  research_molten_metals = "Molten metals productivity",
  research_lubricant_productivity = "Lubricant productivity",
  research_oil_cracking_productivity = "Oil cracking productivity",
  research_oil_processing_productivity = "Oil processing productivity",
  research_plastic = "Plastic productivity",
  research_processing_unit = "Processing unit productivity",
  research_quantum_processor = "Quantum processor productivity",
  research_rails = "Rail productivity",
  research_robot_battery = "Worker robot battery",
  research_rocket_fuel = "Rocket fuel productivity",
  research_rocket_shooting_speed = "Rocket shooting speed",
  research_rockets = "Rocket productivity",
  research_science_pack_productivity = "Science pack productivity",
  research_spoilage_preservation = "Spoilage preservation",
  research_sulfur = "Sulfur productivity",
  research_sulfuric_acid_productivity = "Sulfuric acid productivity",
  research_supercapacitor = "Supercapacitor productivity",
  research_superconductor = "Superconductor productivity",
  research_thruster_fuel_productivity = "Thruster fuel productivity",
  research_thruster_oxidizer_productivity = "Thruster oxidizer productivity",
  research_tungsten = "Tungsten productivity",
  research_walls = "Wall productivity"
}

local base_extension_specs = settings_catalog.base_extension_specs

local function order_slug(value)
  local out = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if out == "" then return "zzz" end
  return out
end

local function fallback_stream_sort_name(key)
  return (key:gsub("^research_", ""):gsub("_", " "))
end

local function stream_sort_name(key)
  return stream_sort_names[key] or fallback_stream_sort_name(key)
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

for key, stream in pairs(C.streams) do
  table.insert(technology_setting_groups, {
    kind = "stream",
    key = key,
    stream = stream,
    sort_name = stream_sort_name(key),
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
      if string.find(setting.name, "^ips%-enable%-") then
        setting.localised_description = append_note(setting.localised_description, settings_note)
      end
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
