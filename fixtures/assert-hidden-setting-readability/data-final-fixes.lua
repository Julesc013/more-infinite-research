local function fail(message)
  error("MIR setting registration validation failed: " .. message)
end

local function assert_startup_setting_readable(name)
  local setting = settings and settings.startup and settings.startup[name]
  if not setting then
    fail("missing startup setting " .. name .. ".")
  end

  if setting.value == nil then
    fail("startup setting " .. name .. " has no readable value.")
  end
end

local governed_stream_keys = {
  "research_advanced_circuit",
  "research_agricultural_growth_speed",
  "research_air_scrubbing_clean_filter",
  "research_armor_components",
  "research_artificial_soil",
  "research_ash_separation",
  "research_bacteria_cultivation",
  "research_batteries",
  "research_belts",
  "research_bioflux",
  "research_breeding",
  "research_bullets",
  "research_cannon_shooting_speed",
  "research_carbon",
  "research_carbon_fiber",
  "research_cargo_bay_unloading_distance",
  "research_cargo_landing_pad_count",
  "research_character_crafting_speed",
  "research_character_mining_speed",
  "research_character_reach",
  "research_character_walking_speed",
  "research_concrete",
  "research_copper",
  "research_copper_cable",
  "research_electric_energy",
  "research_electric_engine",
  "research_electric_shooting_speed",
  "research_electronic_circuit",
  "research_engine",
  "research_explosives",
  "research_flamethrower_shooting_speed",
  "research_flying_robot_frame",
  "research_furnace",
  "research_gears",
  "research_grenades",
  "research_heavy_ammo",
  "research_holmium",
  "research_ice",
  "research_inserters",
  "research_inventory_capacity",
  "research_iron",
  "research_iron_sticks",
  "research_lab_productivity",
  "research_landfill",
  "research_lithium",
  "research_low_density_structure",
  "research_lubricant_productivity",
  "research_mining_drill",
  "research_modules",
  "research_molten_metals",
  "research_oil_cracking_productivity",
  "research_oil_processing_productivity",
  "research_plastic",
  "research_processing_unit",
  "research_quantum_processor",
  "research_rails",
  "research_robot_battery",
  "research_rocket_fuel",
  "research_rocket_shooting_speed",
  "research_rockets",
  "research_science_pack_productivity",
  "research_spoilage_preservation",
  "research_sulfur",
  "research_sulfuric_acid_productivity",
  "research_supercapacitor",
  "research_superconductor",
  "research_thruster_fuel_productivity",
  "research_thruster_oxidizer_productivity",
  "research_tungsten",
  "research_walls"
}

local stream_setting_patterns = {
  "ips-enable-%s",
  "ips-cost-base-%s",
  "ips-cost-growth-%s",
  "ips-max-level-%s",
  "ips-research-time-%s"
}

local target_line_omitted_stream_keys = {
  -- The Factorio 2.0 backport omits these 2.1-only cargo direct-effect streams.
  research_cargo_bay_unloading_distance = true,
  research_cargo_landing_pad_count = true
}

local function startup_setting_exists(name)
  return settings and settings.startup and settings.startup[name] ~= nil
end

local base_extension_keys = {
  "braking-force",
  "inserter-capacity-bonus",
  "laser-shooting-speed",
  "research-speed",
  "weapon-shooting-speed",
  "worker-robots-storage"
}

local base_setting_patterns = {
  "mir-enable-%s",
  "mir-cost-base-%s",
  "mir-cost-growth-%s",
  "mir-max-level-%s",
  "mir-research-time-%s"
}

for _, stream_key in ipairs(governed_stream_keys) do
  local enable_name = string.format("ips-enable-%s", stream_key)
  if not target_line_omitted_stream_keys[stream_key] or startup_setting_exists(enable_name) then
    for _, setting_pattern in ipairs(stream_setting_patterns) do
      assert_startup_setting_readable(string.format(setting_pattern, stream_key))
    end
  end
end

for _, base_key in ipairs(base_extension_keys) do
  for _, setting_pattern in ipairs(base_setting_patterns) do
    assert_startup_setting_readable(string.format(setting_pattern, base_key))
  end
end

if not (mods and mods["space-age"]) then
  local techs = data.raw.technology or {}
  for _, tech_name in ipairs({
    "recipe-prod-research_tungsten-1",
    "recipe-prod-research_lithium-1",
    "recipe-prod-research_holmium-1",
    "recipe-prod-research_thruster_fuel_productivity-1",
    "recipe-prod-research_thruster_oxidizer_productivity-1",
    "recipe-prod-research_breeding-1",
    "recipe-prod-research_agricultural_growth_speed-1",
    "recipe-prod-research_cargo_bay_unloading_distance-1",
    "recipe-prod-research_cargo_landing_pad_count-1",
    "recipe-prod-research_spoilage_preservation-1"
  }) do
    if techs[tech_name] then
      fail("base-only setting fixture expected " .. tech_name .. " to remain ungenerateable.")
    end
  end
end
