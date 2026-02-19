local C = require("prototypes.config")
local defaults = require("defaults")

local settings_data = {}
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

table.insert(settings_data, {
  type = "bool-setting",
  name = "ips-require-space-gate",
  setting_type = "startup",
  default_value = true,
  order = "a-00",
  localised_name = {"mod-setting-name.ips-require-space-gate"},
  localised_description = {"mod-setting-description.ips-require-space-gate"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-prefer-this-mod-for-competing-techs",
  setting_type = "startup",
  default_value = true,
  order = "a-01",
  localised_name = {"mod-setting-name.mir-prefer-this-mod-for-competing-techs"},
  localised_description = {"mod-setting-description.mir-prefer-this-mod-for-competing-techs"}
})

local stream_order = {
  "research_breeding",
  "research_plastic",
  "research_sulfur",
  "research_batteries",
  "research_explosives",
  "research_gears",
  "research_iron_sticks",
  "research_copper_cable",
  "research_electronic_circuit",
  "research_advanced_circuit",
  "research_processing_unit",
  "research_low_density_structure",
  "research_rocket_fuel",
  "research_copper",
  "research_iron",
  "research_engine",
  "research_electric_engine",
  "research_flying_robot_frame",
  "research_tungsten",
  "research_holmium",
  "research_supercapacitor",
  "research_superconductor",
  "research_bioflux",
  "research_carbon_fiber",
  "research_lithium",
  "research_quantum_processor",
  "research_modules",
  "research_belts",
  "research_inserters",
  "research_bullets",
  "research_rockets",
  "research_walls",
  "research_grenades",
  "research_rails",
  "research_concrete",
  "research_furnace",
  "research_mining_drill",
  "research_electric_energy",
  "research_science_pack_productivity",
  "research_rocket_shooting_speed",
  "research_flamethrower_shooting_speed",
  "research_electric_shooting_speed",
  "research_character_mining_speed",
  "research_character_crafting_speed",
  "research_character_walking_speed",
  "research_character_reach",
  "research_character_trash_slots",
  "research_inventory_capacity",
  "research_robot_battery"
}

local known = {}
for _, key in ipairs(stream_order) do known[key] = true end

local extras = {}
for key, _ in pairs(C.streams) do
  if not known[key] then table.insert(extras, key) end
end
table.sort(extras)
for _, key in ipairs(extras) do table.insert(stream_order, key) end

for _, key in ipairs(stream_order) do
  local stream = C.streams[key]
  if stream then
    local tech_locale = {"technology-name.more-infinite-research."..key}
    table.insert(settings_data, {
      type = "bool-setting",
      name = "ips-enable-"..key,
      setting_type = "startup",
      default_value = default_enabled(key, stream),
      order = "b-"..key.."-0",
      localised_name = {"mod-setting-name.ips-enable-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-enable-stream", tech_locale}
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "ips-cost-base-"..key,
      setting_type = "startup",
      default_value = default_base_cost(key, stream),
      minimum_value = 1,
      maximum_value = 2147483647,
      order = "b-"..key.."-1",
      localised_name = {"mod-setting-name.ips-cost-base-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-cost-base-stream", tech_locale}
    })
    table.insert(settings_data, {
      type = "double-setting",
      name = "ips-cost-growth-"..key,
      setting_type = "startup",
      default_value = default_growth_factor(key, stream),
      minimum_value = 1,
      order = "b-"..key.."-2",
      localised_name = {"mod-setting-name.ips-cost-growth-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-cost-growth-stream", tech_locale}
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "ips-max-level-"..key,
      setting_type = "startup",
      default_value = default_max_level_setting(key, stream),
      minimum_value = 0,
      maximum_value = 2147483647,
      order = "b-"..key.."-3",
      localised_name = {"mod-setting-name.ips-max-level-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-max-level-stream", tech_locale}
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "ips-research-time-"..key,
      setting_type = "startup",
      default_value = default_research_time_setting(key, stream),
      minimum_value = 0,
      maximum_value = 2147483647,
      order = "b-"..key.."-4",
      localised_name = {"mod-setting-name.mir-research-time", tech_locale},
      localised_description = {"mod-setting-description.mir-research-time", tech_locale}
    })
  end
end

local base_extensions = {
  { key = "braking-force", order = "c-01" },
  { key = "research-speed", order = "c-02" },
  { key = "worker-robots-storage", order = "c-03" },
  { key = "inserter-capacity-bonus", order = "c-04" },
  { key = "weapon-shooting-speed", order = "c-05" },
  { key = "laser-shooting-speed", order = "c-06" }
}

for _, spec in ipairs(base_extensions) do
  local defaults_spec = base_defaults[spec.key] or {}
  local enabled_default = defaults_spec.enabled
  if enabled_default == nil then enabled_default = true end
  local base_default = tonumber(defaults_spec.base_cost) or 0
  if base_default < 0 then base_default = 0 end
  local growth_default = tonumber(defaults_spec.growth_factor) or 0
  if growth_default < 0 then growth_default = 0 end
  local research_time_default = tonumber(defaults_spec.research_time) or 60
  if research_time_default < 1 then research_time_default = 60 end
  local max_level_default = defaults_spec.max_level
  if max_level_default == nil or max_level_default == "infinite" then
    max_level_default = 0
  else
    local num = tonumber(max_level_default)
    if not num or num <= 0 then
      max_level_default = 0
    else
      max_level_default = math.floor(num + 0.5)
    end
  end
  local locale = {"technology-name."..spec.key}
  local base_order = spec.order .. "-a"
  table.insert(settings_data, {
    type = "bool-setting",
    name = "mir-enable-"..spec.key,
    setting_type = "startup",
    default_value = enabled_default,
    order = base_order.."",
    localised_name = {"mod-setting-name.mir-enable-base-tech", locale},
    localised_description = {"mod-setting-description.mir-enable-base-tech", locale}
  })
  table.insert(settings_data, {
    type = "int-setting",
    name = "mir-cost-base-"..spec.key,
    setting_type = "startup",
    default_value = math.floor(base_default + 0.5),
    minimum_value = 0,
    maximum_value = 2147483647,
    order = base_order.."-1",
    localised_name = {"mod-setting-name.mir-cost-base", locale},
    localised_description = {"mod-setting-description.mir-cost-base", locale}
  })
  table.insert(settings_data, {
    type = "double-setting",
    name = "mir-cost-growth-"..spec.key,
    setting_type = "startup",
    default_value = growth_default,
    minimum_value = 0,
    order = base_order.."-2",
    localised_name = {"mod-setting-name.mir-cost-growth", locale},
    localised_description = {"mod-setting-description.mir-cost-growth", locale}
  })
  table.insert(settings_data, {
    type = "int-setting",
    name = "mir-max-level-"..spec.key,
    setting_type = "startup",
    default_value = max_level_default,
    minimum_value = 0,
    maximum_value = 2147483647,
    order = base_order.."-3",
    localised_name = {"mod-setting-name.ips-max-level-stream", locale},
    localised_description = {"mod-setting-description.ips-max-level-stream", locale}
  })
  table.insert(settings_data, {
    type = "int-setting",
    name = "mir-research-time-"..spec.key,
    setting_type = "startup",
    default_value = math.floor(research_time_default + 0.5),
    minimum_value = 0,
    maximum_value = 2147483647,
    order = base_order.."-4",
    localised_name = {"mod-setting-name.mir-research-time", locale},
    localised_description = {"mod-setting-description.mir-research-time", locale}
  })
end

data:extend(settings_data)
