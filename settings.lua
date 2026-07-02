local C = require("prototypes.config")
local defaults = require("defaults")
local pipeline_extent_settings = require("prototypes.pipeline-extent-settings")

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

local function append_note(description, note)
  if not note then return description end
  return {"", description, "\n\n", note}
end

table.insert(settings_data, {
  type = "bool-setting",
  name = "ips-require-space-gate",
  setting_type = "startup",
  default_value = false,
  order = "a-010",
  localised_name = {"mod-setting-name.ips-require-space-gate"},
  localised_description = {"mod-setting-description.ips-require-space-gate"}
})

table.insert(settings_data, {
  type = "string-setting",
  name = "mir-science-pack-ingredient-policy",
  setting_type = "startup",
  default_value = "configured",
  allowed_values = {"configured", "space", "space-and-promethium", "all-official", "all"},
  order = "a-020",
  localised_name = {"mod-setting-name.mir-science-pack-ingredient-policy"},
  localised_description = {"mod-setting-description.mir-science-pack-ingredient-policy"}
})

table.insert(settings_data, {
  type = "string-setting",
  name = "mir-lab-incompatibility-policy",
  setting_type = "startup",
  default_value = "reduce",
  allowed_values = {"reduce", "skip"},
  order = "a-030",
  localised_name = {"mod-setting-name.mir-lab-incompatibility-policy"},
  localised_description = {"mod-setting-description.mir-lab-incompatibility-policy"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-prefer-this-mod-for-competing-techs",
  setting_type = "startup",
  default_value = true,
  order = "a-100",
  localised_name = {"mod-setting-name.mir-prefer-this-mod-for-competing-techs"},
  localised_description = {"mod-setting-description.mir-prefer-this-mod-for-competing-techs"}
})

table.insert(settings_data, {
  type = "string-setting",
  name = "mir-adjust-vanilla-weapon-speed-techs",
  setting_type = "startup",
  default_value = "off",
  allowed_values = {"off", "only-when-dedicated-tech-enabled", "always"},
  order = "a-110",
  localised_name = {"mod-setting-name.mir-adjust-vanilla-weapon-speed-techs"},
  localised_description = {"mod-setting-description.mir-adjust-vanilla-weapon-speed-techs"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-use-installed-space-age-icons",
  setting_type = "startup",
  default_value = false,
  order = "a-120",
  localised_name = {"mod-setting-name.mir-use-installed-space-age-icons"},
  localised_description = {"mod-setting-description.mir-use-installed-space-age-icons"}
})

table.insert(settings_data, {
  type = "string-setting",
  name = "mir-pipeline-extent-multiplier",
  setting_type = "startup",
  default_value = pipeline_extent_settings.default_value,
  allowed_values = pipeline_extent_settings.allowed_values,
  order = "a-130",
  localised_name = {"mod-setting-name.mir-pipeline-extent-multiplier"},
  localised_description = {"mod-setting-description.mir-pipeline-extent-multiplier"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-debug-generation-report",
  setting_type = "startup",
  default_value = false,
  order = "a-900",
  localised_name = {"mod-setting-name.mir-debug-generation-report"},
  localised_description = {"mod-setting-description.mir-debug-generation-report"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-debug-recipe-matches",
  setting_type = "startup",
  default_value = false,
  order = "a-910",
  localised_name = {"mod-setting-name.mir-debug-recipe-matches"},
  localised_description = {"mod-setting-description.mir-debug-recipe-matches"}
})

table.insert(settings_data, {
  type = "bool-setting",
  name = "mir-debug-scripted-effects",
  setting_type = "startup",
  default_value = false,
  order = "a-920",
  localised_name = {"mod-setting-name.mir-debug-scripted-effects"},
  localised_description = {"mod-setting-description.mir-debug-scripted-effects"}
})

local stream_sort_names = {
  research_advanced_circuit = "Advanced circuit productivity",
  research_agricultural_growth_speed = "Agricultural growth speed",
  research_armor_components = "Armor component productivity",
  research_batteries = "Battery productivity",
  research_belts = "Transport belt productivity",
  research_bioflux = "Bioflux productivity",
  research_breeding = "Breeding productivity",
  research_bullets = "Bullet productivity",
  research_cannon_shooting_speed = "Cannon shooting speed",
  research_cargo_bay_unloading_distance = "Cargo bay unloading distance",
  research_cargo_landing_pad_count = "Cargo landing pad count",
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
  research_inserters = "Inserter productivity",
  research_inventory_capacity = "Character inventory slots",
  research_iron = "Iron plate productivity",
  research_iron_sticks = "Iron stick productivity",
  research_lab_productivity = "Research productivity",
  research_lithium = "Lithium productivity",
  research_low_density_structure = "Low density structure productivity",
  research_mining_drill = "Mining drill productivity",
  research_modules = "Module productivity",
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
  research_stone_products = "Stone product productivity",
  research_sulfur = "Sulfur productivity",
  research_sulfuric_acid_productivity = "Sulfuric acid productivity",
  research_supercapacitor = "Supercapacitor productivity",
  research_superconductor = "Superconductor productivity",
  research_thruster_fuel_productivity = "Thruster fuel productivity",
  research_thruster_oxidizer_productivity = "Thruster oxidizer productivity",
  research_tungsten = "Tungsten productivity",
  research_walls = "Wall productivity"
}

local base_extension_specs = {
  { key = "braking-force", sort_name = "Braking force" },
  { key = "inserter-capacity-bonus", sort_name = "Inserter capacity bonus" },
  { key = "laser-shooting-speed", sort_name = "Laser shooting speed" },
  { key = "research-speed", sort_name = "Lab research speed" },
  { key = "weapon-shooting-speed", sort_name = "Weapon shooting speed" },
  { key = "worker-robots-storage", sort_name = "Worker robot cargo size" }
}

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

local function group_order_prefix(group)
  local bucket = group.enabled and "100" or "000"
  return "b-" .. bucket .. "-" .. order_slug(group.sort_name) .. "-" .. group.kind .. "-" .. group.key
end

local technology_setting_groups = {}

for key, stream in pairs(C.streams) do
  table.insert(technology_setting_groups, {
    kind = "stream",
    key = key,
    stream = stream,
    sort_name = stream_sort_name(key),
    enabled = default_enabled(key, stream)
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
    enabled = enabled
  })
end

table.sort(technology_setting_groups, function(a, b)
  local disabled_a = not a.enabled
  local disabled_b = not b.enabled
  if disabled_a ~= disabled_b then return disabled_a end
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
    table.insert(settings_data, {
      type = "bool-setting",
      name = "ips-enable-"..key,
      setting_type = "startup",
      default_value = group.enabled,
      order = order_prefix.."-0",
      localised_name = {"mod-setting-name.ips-enable-stream", tech_locale},
      localised_description = append_note({"mod-setting-description.ips-enable-stream", tech_locale}, settings_note)
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "ips-cost-base-"..key,
      setting_type = "startup",
      default_value = default_base_cost(key, stream),
      minimum_value = 1,
      maximum_value = 2147483647,
      order = order_prefix.."-1",
      localised_name = {"mod-setting-name.ips-cost-base-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-cost-base-stream", tech_locale}
    })
    table.insert(settings_data, {
      type = "double-setting",
      name = "ips-cost-growth-"..key,
      setting_type = "startup",
      default_value = default_growth_factor(key, stream),
      minimum_value = 1,
      order = order_prefix.."-2",
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
      order = order_prefix.."-3",
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
      order = order_prefix.."-4",
      localised_name = {"mod-setting-name.ips-research-time-stream", tech_locale},
      localised_description = {"mod-setting-description.ips-research-time-stream", tech_locale}
    })
  else
    local spec = group.spec
    local defaults_spec = group.defaults_spec
    local enabled_default = group.enabled
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
    table.insert(settings_data, {
      type = "bool-setting",
      name = "mir-enable-"..spec.key,
      setting_type = "startup",
      default_value = enabled_default,
      order = order_prefix.."-0",
      localised_name = {"mod-setting-name.mir-enable-base-tech", locale},
      localised_description = append_note({"mod-setting-description.mir-enable-base-tech", locale}, defaults_spec.settings_note)
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "mir-cost-base-"..spec.key,
      setting_type = "startup",
      default_value = math.floor(base_default + 0.5),
      minimum_value = 0,
      maximum_value = 2147483647,
      order = order_prefix.."-1",
      localised_name = {"mod-setting-name.mir-cost-base", locale},
      localised_description = {"mod-setting-description.mir-cost-base", locale}
    })
    table.insert(settings_data, {
      type = "double-setting",
      name = "mir-cost-growth-"..spec.key,
      setting_type = "startup",
      default_value = growth_default,
      minimum_value = 0,
      order = order_prefix.."-2",
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
      order = order_prefix.."-3",
      localised_name = {"mod-setting-name.mir-max-level", locale},
      localised_description = {"mod-setting-description.mir-max-level", locale}
    })
    table.insert(settings_data, {
      type = "int-setting",
      name = "mir-research-time-"..spec.key,
      setting_type = "startup",
      default_value = math.floor(research_time_default + 0.5),
      minimum_value = 0,
      maximum_value = 2147483647,
      order = order_prefix.."-4",
      localised_name = {"mod-setting-name.mir-research-time", locale},
      localised_description = {"mod-setting-description.mir-research-time", locale}
    })
  end
end

data:extend(settings_data)
