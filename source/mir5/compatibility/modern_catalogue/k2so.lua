-- Exact K2 Space-Obscure F210 deltas. This body is loaded only after all four
-- K2SO markers and Space Age are active; it holds no general modpack discovery.
local function recipe_effects(entries)
  local out = {}
  for index = 1, #entries, 2 do out[#out + 1] = {recipe = entries[index], scale = entries[index + 1]} end
  return out
end

local function direct_effect(type_name, scale, ammo_category)
  local effect = {type = type_name, scale = scale, raw = false}
  if ammo_category then effect.ammo_category = ammo_category end
  return effect
end

return {
  product_bindings = {
    {family="research_science_pack_productivity", weight=1, reject_explicit_productivity_denial=true,
      products={{type="item",name="kr-advanced-tech-card"}, {type="item",name="kr-matter-tech-card"},
        {type="item",name="kr-singularity-tech-card"}}},
  },
  definition_overrides = {
    research_artificial_soil = {
      science = "science_production_agricultural_space",
      prerequisites = {},
    },
    research_belts = {
      automatic_recipe_targets = {
        ["kr-advanced-loader"]=true, ["kr-loader"]=true, ["kr-superior-loader"]=true,
        ["kr-superior-splitter"]=true, ["kr-superior-transport-belt"]=true, ["kr-superior-underground-belt"]=true,
      },
      science = "science_production_space",
      prerequisites = {},
      effects = recipe_effects({
        "splitter", 1, "transport-belt", 1, "underground-belt", 1,
        "fast-splitter", 0.5, "fast-transport-belt", 0.5, "fast-underground-belt", 0.5, "kr-fast-loader", 0.5,
        "express-splitter", 0.2, "express-transport-belt", 0.2, "express-underground-belt", 0.2, "kr-express-loader", 0.2,
        "turbo-splitter", 0.1, "turbo-transport-belt", 0.1, "turbo-underground-belt", 0.1,
        "kr-advanced-loader", 0.05, "kr-loader", 0.05, "kr-superior-loader", 0.05,
        "kr-superior-splitter", 0.05, "kr-superior-transport-belt", 0.05, "kr-superior-underground-belt", 0.05,
      }),
      icon = "__Krastorio2Assets__/technologies/logistics-1.png",
    },
    research_breeding = {
      effects = recipe_effects({"biter-egg", 1, "fish-breeding", 1, "kr-biter-egg-upcycling", 1, "pentapod-egg", 1}),
    },
    research_bullets = {
      science = "science_production_space", prerequisites = {},
      effects = recipe_effects({"firearm-magazine", 1, "shotgun-shell", 1, "piercing-rounds-magazine", 0.5, "piercing-shotgun-shell", 0.5}),
    },
    research_carbon = {
      science = "science_production_space", prerequisites = {},
      effects = recipe_effects({"carbon", 1, "kr-matter-to-carbon", 1, "burnt-spoilage", 0.5, "coal-synthesis", 0.2}),
    },
    research_carbon_fiber = {
      effects = recipe_effects({"carbon-fiber", 1, "kr-crush-stack-inserter", 1}),
    },
    research_cargo_bay_unloading_distance = {
      science = "science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
      prerequisites = {"landing-pad-unloading-bay"},
    },
    research_cargo_landing_pad_count = {
      science = "science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
      prerequisites = {"rocket-silo"},
    },
    research_character_mining_speed = {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png"},
    research_character_reach = {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png"},
    research_concrete = {
      science = "science_production_space", prerequisites = {},
      effects = recipe_effects({
        "stone-brick", 1, "concrete", 0.5, "concrete-from-molten-iron", 0.5, "hazard-concrete", 0.5,
        "kr-refined-concrete-from-molten-iron", 0.2, "refined-concrete", 0.2, "refined-hazard-concrete", 0.2,
      }),
    },
    research_copper = {
      effects = recipe_effects({"casting-copper", 1, "copper-plate", 1, "kr-copper-plate-from-enriched-copper", 1, "kr-matter-to-copper-plate", 1}),
      icon = "__Krastorio2Assets__/icons/items/copper-plate.png", icon_size = 64,
    },
    research_copper_cable = {
      effects = recipe_effects({"casting-copper-cable", 1, "copper-cable", 1, "kr-copper-cable-from-copper-ore", 1, "kr-copper-cable-from-enriched-copper", 1}),
    },
    research_electronic_circuit = {effects = recipe_effects({"electronic-circuit", 1, "kr-electronic-circuit-wood", 1})},
    research_flamethrower_shooting_speed = {science = "science_production_space", prerequisites = {"flamethrower"}},
    research_grenades = {science = "science_production_space", prerequisites = {}},
    research_heavy_ammo = {
      science = "science_production_metallurgic_space", prerequisites = {},
      effects = recipe_effects({
        "cannon-shell", 1, "explosive-cannon-shell", 0.5, "explosive-uranium-cannon-shell", 0.2, "uranium-cannon-shell", 0.2,
        "artillery-shell", 0.1, "kr-antimatter-artillery-shell", 0.1, "kr-nuclear-artillery-shell", 0.1, "railgun-ammo", 0.1,
      }),
    },
    research_holmium = {effects = recipe_effects({"holmium-plate", 1, "kr-matter-to-holmium-plate", 1})},
    research_ice = {
      science = "science_production_space_cryogenic", prerequisites = {},
      effects = recipe_effects({"ammoniacal-solution-separation", 1, "kr-matter-to-ice", 1}),
    },
    research_inserters = {
      automatic_recipe_targets = {["kr-superior-inserter"]=true, ["kr-superior-long-inserter"]=true},
      science = "science_production_space", prerequisites = {},
      effects = recipe_effects({
        "burner-inserter", 1, "inserter", 1, "fast-inserter", 0.5, "long-handed-inserter", 0.5,
        "bulk-inserter", 0.2, "stack-inserter", 0.1, "kr-superior-inserter", 0.1, "kr-superior-long-inserter", 0.1,
      }),
    },
    research_iron = {
      effects = recipe_effects({"casting-iron", 1, "iron-plate", 1, "kr-iron-plate-from-enriched-iron", 1, "kr-matter-to-iron-plate", 1}),
      icon = "__Krastorio2Assets__/icons/items/iron-plate.png", icon_size = 64,
    },
    research_iron_sticks = {
      effects = recipe_effects({"casting-iron-stick", 1, "iron-stick", 1, "kr-iron-stick-from-enriched-iron", 1, "kr-iron-stick-from-iron-ore", 1}),
    },
    research_landfill = {
      science = "science_production_metallurgic_space", prerequisites = {},
      effects = recipe_effects({"kr-landfill-with-sand", 1, "landfill", 1, "foundation", 0.5}),
    },
    research_mining_drill = {
      effects = recipe_effects({"burner-mining-drill", 1, "electric-mining-drill", 0.5, "big-mining-drill", 0.25, "kr-quarry-drill", 0.25}),
      icon = "__Krastorio2Assets__/icons/entities/electric-mining-drill.png", icon_size = 64,
    },
    research_platform = {science = "science_production_space_cryogenic", prerequisites = {}},
    research_rails = {science = "science_production_space", prerequisites = {}},
    research_robot_battery = {science = "science_production_space", prerequisites = {}},
    research_science_pack_productivity = {
      science = "science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium_k2",
      prerequisites = {},
      effects = recipe_effects({
        "agricultural-science-pack", 1, "agricultural-science-pack-cooling", 1, "automation-science-pack", 1, "chemical-science-pack", 1,
        "cryogenic-science-pack", 1, "cryogenic-science-pack-cooling", 1, "electromagnetic-science-pack", 1, "electromagnetic-science-pack-cooling", 1,
        "kr-advanced-tech-card", 1, "kr-advanced-tech-card-cooling", 1, "kr-matter-tech-card", 1, "kr-matter-tech-card-cooling", 1,
        "kr-singularity-tech-card", 1, "kr-singularity-tech-card-cooling", 1, "logistic-science-pack", 1,
        "metallurgic-science-pack", 1, "metallurgic-science-pack-cooling", 1, "military-science-pack", 1,
        "production-science-pack", 1, "production-science-pack-cooling", 1, "promethium-science-pack", 1, "promethium-science-pack-cooling", 1,
        "space-science-pack", 1, "space-science-pack-cooling", 1, "utility-science-pack", 1, "utility-science-pack-cooling", 1,
      }),
    },
    research_sulfur = {effects = recipe_effects({"biosulfur", 1, "kr-matter-to-sulfur", 1, "sulfur", 1})},
    research_thruster_fuel_productivity = {
      science = "science_production_space_agricultural", prerequisites = {},
      effects = recipe_effects({"advanced-thruster-fuel", 1, "kr-liquid-hydrogen", 1, "thruster-fuel", 1}),
    },
    research_thruster_oxidizer_productivity = {
      science = "science_production_space_agricultural", prerequisites = {},
      effects = recipe_effects({"advanced-thruster-oxidizer", 1, "kr-liquid-oxygen", 1, "thruster-oxidizer", 1}),
    },
    research_tungsten = {effects = recipe_effects({"kr-matter-to-tungsten-carbide", 1, "kr-matter-to-tungsten-plate", 1, "tungsten-carbide", 1, "tungsten-plate", 1})},
    research_walls = {science = "science_production_space", prerequisites = {}},
  },
  continuation_overrides = {
    braking_force = {
      science = "science_production_utility_space",
      prerequisites = {"braking-force-6", "braking-force-7"},
    },
    laser_shooting_speed = {
      science = "science_utility_space",
      prerequisites = {"laser-shooting-speed-6", "laser-shooting-speed-7"},
      effects = {direct_effect("gun-speed", 0.2, "laser"), direct_effect("gun-speed", 0.2, "kr-impulse-rifle")},
    },
    research_speed = {
      science = "science_production_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium_k2",
      prerequisites = {"research-speed-5", "utility-science-pack", "research-speed-6"},
    },
    weapon_shooting_speed = {
      science = "science_utility_space",
      prerequisites = {"weapon-shooting-speed-5", "utility-science-pack", "weapon-shooting-speed-6"},
      effects = {
        direct_effect("gun-speed", 0.375, "bullet"), direct_effect("gun-speed", 0.375, "shotgun-shell"),
        direct_effect("gun-speed", 0.375, "kr-pistol"), direct_effect("gun-speed", 0.375, "kr-anti-materiel-rifle-ammo"),
        direct_effect("gun-speed", 0.5, "kr-railgun-shell"), direct_effect("gun-speed", 0.5, "kr-turret-missile"),
        direct_effect("gun-speed", 0.5, "kr-heavy-rocket"),
      },
    },
  },
  native_owners = {
    {family = "research_low_density_structure", id = "low-density-structure-productivity", setting = "ips-max-level-research_low_density_structure",
      expected = {enabled = nil, max_level = "infinite", count_formula = "1.5^L*1000", research_time = 60,
        base_cost = 1500, growth_factor = 1.5, linear_increment = 0, effect_change = 0.1},
      admission = {recipes = {"low-density-structure", "casting-low-density-structure"}, effect_type = "change-recipe-productivity"}},
    {family = "research_plastic", id = "plastic-bar-productivity", setting = "ips-max-level-research_plastic",
      expected = {enabled = nil, max_level = "infinite", count_formula = "1.5^L*1000", research_time = 60,
        base_cost = 1500, growth_factor = 1.5, linear_increment = 0, effect_change = 0.1},
      admission = {recipes = {"plastic-bar", "bioplastic"}, effect_type = "change-recipe-productivity"}},
    {family = "research_processing_unit", id = "processing-unit-productivity", setting = "ips-max-level-research_processing_unit",
      expected = {enabled = nil, max_level = "infinite", count_formula = "1.5^L*1000", research_time = 60,
        base_cost = 1500, growth_factor = 1.5, linear_increment = 0, effect_change = 0.1},
      admission = {recipes = {"processing-unit", "kr-bio-processing-circuit"}, effect_type = "change-recipe-productivity"}},
    {family = "research_rocket_fuel", id = "rocket-fuel-productivity", setting = "ips-max-level-research_rocket_fuel",
      expected = {enabled = nil, max_level = "infinite", count_formula = "1.5^L*1000", research_time = 60,
        base_cost = 1500, growth_factor = 1.5, linear_increment = 0, effect_change = 0.1},
      admission = {recipes = {"rocket-fuel", "rocket-fuel-from-jelly", "ammonia-rocket-fuel", "kr-rocket-fuel-with-hydrogen-chloride"}, effect_type = "change-recipe-productivity"}},
  },
  imersite = true,
}
