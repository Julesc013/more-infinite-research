-- Exact private F210 catalogue input recovered from
-- spec/inventory/modern-f210-470.json. This fixture enumerates finite
-- identities; it never discovers technology or recipe families at runtime.
local function rows(names, excluded)
  local blocked, out = {}, {}
  for _, name in ipairs(excluded or {}) do blocked[name] = true end
  for _, name in ipairs(names) do
    if not blocked[name] then out[#out + 1] = {name=name} end
  end
  return out
end

local function credits(public, descriptors)
  local present, out = {}, {}
  for _, row in ipairs(public) do present[row.name] = true end
  for _, descriptor in ipairs(descriptors) do
    if present[descriptor[2]] then
      out[#out + 1] = "mir-native-credit-" .. descriptor[1] .. "-" .. descriptor[3] .. "-positive"
      out[#out + 1] = "mir-native-credit-" .. descriptor[1] .. "-" .. descriptor[3] .. "-negative"
    end
  end
  return out
end

local base_names = {
  "braking-force-8", "inserter-capacity-bonus-8", "laser-shooting-speed-8",
  "recipe-prod-research_advanced_circuit-1", "recipe-prod-research_batteries-1",
  "recipe-prod-research_belts-1", "recipe-prod-research_bullets-1",
  "recipe-prod-research_cannon_shooting_speed-1", "recipe-prod-research_character_crafting_speed-1",
  "recipe-prod-research_character_mining_speed-1", "recipe-prod-research_character_reach-1",
  "recipe-prod-research_character_walking_speed-1", "recipe-prod-research_concrete-1",
  "recipe-prod-research_copper-1", "recipe-prod-research_copper_cable-1",
  "recipe-prod-research_electric_energy-1", "recipe-prod-research_electric_engine-1",
  "recipe-prod-research_electric_shooting_speed-1", "recipe-prod-research_electronic_circuit-1",
  "recipe-prod-research_engine-1", "recipe-prod-research_explosives-1",
  "recipe-prod-research_flamethrower_shooting_speed-1", "recipe-prod-research_flying_robot_frame-1",
  "recipe-prod-research_furnace-1", "recipe-prod-research_gears-1", "recipe-prod-research_grenades-1",
  "recipe-prod-research_heavy_ammo-1", "recipe-prod-research_inserters-1",
  "recipe-prod-research_inventory_capacity-1", "recipe-prod-research_iron-1",
  "recipe-prod-research_iron_sticks-1", "recipe-prod-research_lab_productivity-1",
  "recipe-prod-research_landfill-1", "recipe-prod-research_low_density_structure-1",
  "recipe-prod-research_lubricant_productivity-1", "recipe-prod-research_mining_drill-1",
  "recipe-prod-research_modules-1", "recipe-prod-research_oil_cracking_productivity-1",
  "recipe-prod-research_oil_processing_productivity-1", "recipe-prod-research_plastic-1",
  "recipe-prod-research_processing_unit-1", "recipe-prod-research_rails-1",
  "recipe-prod-research_robot_battery-1", "recipe-prod-research_rocket_fuel-1",
  "recipe-prod-research_rocket_shooting_speed-1", "recipe-prod-research_rockets-1",
  "recipe-prod-research_steel-1", "recipe-prod-research_sulfur-1",
  "recipe-prod-research_sulfuric_acid_productivity-1", "recipe-prod-research_walls-1",
  "research-speed-7", "weapon-shooting-speed-7", "worker-robots-storage-4",
}

local space_age_names = {
  "braking-force-8", "inserter-capacity-bonus-8", "laser-shooting-speed-8",
  "recipe-prod-research_advanced_circuit-1", "recipe-prod-research_agricultural_growth_speed-1",
  "recipe-prod-research_artificial_soil-1", "recipe-prod-research_bacteria_cultivation-1",
  "recipe-prod-research_batteries-1", "recipe-prod-research_belts-1", "recipe-prod-research_bioflux-1",
  "recipe-prod-research_breeding-1", "recipe-prod-research_bullets-1",
  "recipe-prod-research_cannon_shooting_speed-1", "recipe-prod-research_capture_robot_rockets-1",
  "recipe-prod-research_carbon-1", "recipe-prod-research_carbon_fiber-1",
  "recipe-prod-research_cargo_bay_unloading_distance-1", "recipe-prod-research_cargo_landing_pad_count-1",
  "recipe-prod-research_character_crafting_speed-1", "recipe-prod-research_character_mining_speed-1",
  "recipe-prod-research_character_reach-1", "recipe-prod-research_character_walking_speed-1",
  "recipe-prod-research_concrete-1", "recipe-prod-research_copper-1", "recipe-prod-research_copper_cable-1",
  "recipe-prod-research_electric_energy-1", "recipe-prod-research_electric_engine-1",
  "recipe-prod-research_electric_shooting_speed-1", "recipe-prod-research_electronic_circuit-1",
  "recipe-prod-research_engine-1", "recipe-prod-research_explosives-1",
  "recipe-prod-research_flamethrower_shooting_speed-1", "recipe-prod-research_flying_robot_frame-1",
  "recipe-prod-research_furnace-1", "recipe-prod-research_gears-1", "recipe-prod-research_grenades-1",
  "recipe-prod-research_heavy_ammo-1", "recipe-prod-research_holmium-1", "recipe-prod-research_ice-1",
  "recipe-prod-research_inserters-1", "recipe-prod-research_inventory_capacity-1", "recipe-prod-research_iron-1",
  "recipe-prod-research_iron_sticks-1", "recipe-prod-research_landfill-1", "recipe-prod-research_lithium-1",
  "recipe-prod-research_lubricant_productivity-1", "recipe-prod-research_mining_drill-1",
  "recipe-prod-research_modules-1", "recipe-prod-research_molten_metals-1", "recipe-prod-research_nutrients-1",
  "recipe-prod-research_oil_cracking_productivity-1", "recipe-prod-research_oil_processing_productivity-1",
  "recipe-prod-research_platform-1", "recipe-prod-research_quantum_processor-1", "recipe-prod-research_rails-1",
  "recipe-prod-research_robot_battery-1", "recipe-prod-research_rocket_shooting_speed-1",
  "recipe-prod-research_rockets-1", "recipe-prod-research_science_pack_productivity-1",
  "recipe-prod-research_spoilage_preservation-1", "recipe-prod-research_sulfur-1",
  "recipe-prod-research_sulfuric_acid_productivity-1", "recipe-prod-research_supercapacitor-1",
  "recipe-prod-research_superconductor-1", "recipe-prod-research_thruster_fuel_productivity-1",
  "recipe-prod-research_thruster_oxidizer_productivity-1", "recipe-prod-research_tungsten-1",
  "recipe-prod-research_walls-1", "research-speed-7", "weapon-shooting-speed-7", "worker-robots-storage-4",
}

local descriptors = {
  {"research_copper", "recipe-prod-research_copper-1", "copper-plate"},
  {"research_iron", "recipe-prod-research_iron-1", "iron-plate"},
  {"research_breeding", "recipe-prod-research_breeding-1", "fish-breeding"},
  {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "advanced-oil-processing"},
  {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "basic-oil-processing"},
  {"research_oil_processing_productivity", "recipe-prod-research_oil_processing_productivity-1", "coal-liquefaction"},
  {"research_bullets", "recipe-prod-research_bullets-1", "firearm-magazine"},
  {"research_grenades", "recipe-prod-research_grenades-1", "grenade"},
  {"research_lubricant_productivity", "recipe-prod-research_lubricant_productivity-1", "lubricant"},
  {"research_breeding", "recipe-prod-research_breeding-1", "pentapod-egg"},
  {"research_concrete", "recipe-prod-research_concrete-1", "stone-brick"},
  {"research_sulfuric_acid_productivity", "recipe-prod-research_sulfuric_acid_productivity-1", "sulfuric-acid"},
}

local base_public, space_public = rows(base_names), rows(space_age_names)
return {
  target = {
    id = "f210", version = "2.1.23", published_mir = "4.7.21002", mir5 = "5.0.21000",
    space_age_closure = {"elevated-rails", "quality", "recycler", "space-age"},
  },
  force_fields = {
    "train_braking_force_bonus", "inserter_stack_size_bonus", "bulk_inserter_capacity_bonus",
    "laboratory_speed_modifier", "worker_robots_storage_bonus", "manual_crafting_speed_modifier",
    "manual_mining_speed_modifier", "character_reach_distance_bonus", "character_build_distance_bonus",
    "character_resource_reach_distance_bonus", "character_item_drop_distance_bonus",
    "character_running_speed_modifier", "character_inventory_slots_bonus", "character_trash_slot_count",
    "worker_robots_battery_modifier", "max_cargo_bay_unloading_distance", "cargo_landing_pad_limit",
  },
  base = {
    public = base_public, state = rows(base_names), scripted = {},
    recipes = {
      "accumulator", "advanced-circuit", "advanced-oil-processing", "artillery-shell", "atomic-bomb", "basic-oil-processing", "battery", "bulk-inserter", "burner-inserter", "burner-mining-drill", "cannon-shell", "cluster-grenade", "coal-liquefaction", "concrete", "copper-cable", "copper-plate", "efficiency-module", "efficiency-module-2", "efficiency-module-3", "electric-engine-unit", "electric-furnace", "electric-mining-drill", "electronic-circuit", "engine-unit", "explosive-cannon-shell", "explosive-rocket", "explosive-uranium-cannon-shell", "explosives", "express-splitter", "express-transport-belt", "express-underground-belt", "fast-inserter", "fast-splitter", "fast-transport-belt", "fast-underground-belt", "firearm-magazine", "flying-robot-frame", "gate", "grenade", "hazard-concrete", "heavy-oil-cracking", "inserter", "iron-gear-wheel", "iron-plate", "iron-stick", "landfill", "light-oil-cracking", "long-handed-inserter", "low-density-structure", "lubricant", "piercing-rounds-magazine", "piercing-shotgun-shell", "plastic-bar", "processing-unit", "productivity-module", "productivity-module-2", "productivity-module-3", "rail", "refined-concrete", "refined-hazard-concrete", "rocket", "rocket-fuel", "shotgun-shell", "solar-panel", "speed-module", "speed-module-2", "speed-module-3", "splitter", "steel-furnace", "steel-plate", "stone-brick", "stone-furnace", "stone-wall", "sulfur", "sulfuric-acid", "transport-belt", "underground-belt", "uranium-cannon-shell", "uranium-rounds-magazine",
    },
    guns = {"bullet", "cannon-shell", "electric", "flamethrower", "laser", "rocket", "shotgun-shell"},
    credits = credits(base_public, descriptors), native_owners = {},
  },
  space_age = {
    public = space_public,
    state = rows(space_age_names, {"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"}),
    scripted = {"recipe-prod-research_agricultural_growth_speed-1", "recipe-prod-research_spoilage_preservation-1"},
    recipes = {
      "accumulator", "acid-neutralisation", "advanced-circuit", "advanced-oil-processing", "advanced-thruster-fuel", "advanced-thruster-oxidizer", "agricultural-science-pack", "ammoniacal-solution-separation", "artificial-jellynut-soil", "artificial-yumako-soil", "artillery-shell", "atomic-bomb", "automation-science-pack", "basic-oil-processing", "battery", "big-mining-drill", "bioflux", "biolubricant", "biosulfur", "biter-egg", "bulk-inserter", "burner-inserter", "burner-mining-drill", "burnt-spoilage", "cannon-shell", "capture-robot-rocket", "carbon", "carbon-fiber", "casting-copper", "casting-copper-cable", "casting-iron", "casting-iron-gear-wheel", "casting-iron-stick", "chemical-science-pack", "cluster-grenade", "coal-liquefaction", "coal-synthesis", "concrete", "concrete-from-molten-iron", "copper-bacteria-cultivation", "copper-cable", "copper-ore-melting", "copper-plate", "cryogenic-science-pack", "efficiency-module", "efficiency-module-2", "efficiency-module-3", "electric-engine-unit", "electric-furnace", "electric-mining-drill", "electromagnetic-science-pack", "electronic-circuit", "engine-unit", "explosive-cannon-shell", "explosive-rocket", "explosive-uranium-cannon-shell", "explosives", "express-splitter", "express-transport-belt", "express-underground-belt", "fast-inserter", "fast-splitter", "fast-transport-belt", "fast-underground-belt", "firearm-magazine", "fish-breeding", "flying-robot-frame", "foundation", "foundry", "gate", "grenade", "hazard-concrete", "heavy-oil-cracking", "holmium-plate", "ice-platform", "inserter", "iron-bacteria-cultivation", "iron-gear-wheel", "iron-ore-melting", "iron-plate", "iron-stick", "landfill", "light-oil-cracking", "lithium", "lithium-plate", "logistic-science-pack", "long-handed-inserter", "lubricant", "metallurgic-science-pack", "military-science-pack", "molten-copper-from-lava", "molten-iron-from-lava", "nutrients-from-bioflux", "nutrients-from-biter-egg", "nutrients-from-yumako-mash", "overgrowth-jellynut-soil", "overgrowth-yumako-soil", "pentapod-egg", "piercing-rounds-magazine", "piercing-shotgun-shell", "production-science-pack", "productivity-module", "productivity-module-2", "productivity-module-3", "promethium-science-pack", "quality-module", "quality-module-2", "quality-module-3", "quantum-processor", "rail", "rail-ramp", "rail-support", "railgun-ammo", "refined-concrete", "refined-hazard-concrete", "rocket", "shotgun-shell", "simple-coal-liquefaction", "solar-panel", "space-platform-foundation", "space-science-pack", "speed-module", "speed-module-2", "speed-module-3", "splitter", "stack-inserter", "steel-furnace", "stone-brick", "stone-furnace", "stone-wall", "sulfur", "sulfuric-acid", "supercapacitor", "superconductor", "thruster-fuel", "thruster-oxidizer", "transport-belt", "tungsten-carbide", "tungsten-plate", "turbo-splitter", "turbo-transport-belt", "turbo-underground-belt", "underground-belt", "uranium-cannon-shell", "uranium-rounds-magazine", "utility-science-pack",
    },
    guns = {"bullet", "cannon-shell", "electric", "flamethrower", "laser", "rocket", "shotgun-shell", "tesla"},
    credits = credits(space_public, descriptors),
    native_owners = {"low-density-structure-productivity", "plastic-bar-productivity", "processing-unit-productivity", "rocket-fuel-productivity", "steel-plate-productivity"},
  },
}
