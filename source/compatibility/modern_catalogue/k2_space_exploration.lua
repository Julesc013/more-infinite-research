-- Authored F210 K2 + Space Exploration field deltas over the SE profile.
-- Only changed fields are repeated. Collection and emission belong to the caller.
return {
  additions = {},
  continuation_overrides = {
    inserter_capacity_bonus = {science = "science_se_k2_inserter_capacity_bonus"},
    laser_shooting_speed = {
      effects = {
        {ammo_category = "laser", raw = false, scale = 0.2, type = "gun-speed"},
        {ammo_category = "cryogun", raw = false, scale = 1, type = "gun-speed"},
        {ammo_category = "kr-impulse-rifle", raw = false, scale = 0.2, type = "gun-speed"}
      }
    },
    research_speed = {
      prerequisites = {"research-speed-6", "kr-singularity-tech-card", "se-deep-space-science-pack-4"},
      science = "science_se_k2_research_speed"
    },
    weapon_shooting_speed = {
      effects = {
        {ammo_category = "bullet", raw = false, scale = 0.375, type = "gun-speed"},
        {ammo_category = "shotgun-shell", raw = false, scale = 0.375, type = "gun-speed"},
        {ammo_category = "railgun", raw = false, scale = 1.25, type = "gun-speed"},
        {ammo_category = "kr-pistol", raw = false, scale = 0.375, type = "gun-speed"},
        {ammo_category = "kr-anti-materiel-rifle-ammo", raw = false, scale = 0.375, type = "gun-speed"},
        {ammo_category = "kr-railgun-shell", raw = false, scale = 0.5, type = "gun-speed"},
        {ammo_category = "kr-turret-missile", raw = false, scale = 0.5, type = "gun-speed"},
        {ammo_category = "kr-heavy-rocket", raw = false, scale = 0.5, type = "gun-speed"}
      }
    },
    worker_robots_storage = {science = "science_se_k2_worker_robots_storage"}
  },
  definition_overrides = {
    research_belts = {
      effects = {
        {recipe = "splitter", scale = 1},
        {recipe = "transport-belt", scale = 1},
        {recipe = "underground-belt", scale = 1},
        {recipe = "fast-splitter", scale = 0.5},
        {recipe = "fast-transport-belt", scale = 0.5},
        {recipe = "fast-underground-belt", scale = 0.5},
        {recipe = "kr-fast-loader", scale = 0.5},
        {recipe = "express-splitter", scale = 0.2},
        {recipe = "express-transport-belt", scale = 0.2},
        {recipe = "express-underground-belt", scale = 0.2},
        {recipe = "kr-express-loader", scale = 0.2},
        {recipe = "kr-advanced-loader", scale = 0.05},
        {recipe = "kr-advanced-splitter", scale = 0.05},
        {recipe = "kr-advanced-transport-belt", scale = 0.05},
        {recipe = "kr-advanced-underground-belt", scale = 0.05},
        {recipe = "kr-loader", scale = 0.05},
        {recipe = "kr-se-deep-space-loader-black", scale = 0.05},
        {recipe = "kr-se-loader", scale = 0.05},
        {recipe = "kr-superior-loader", scale = 0.05},
        {recipe = "kr-superior-splitter", scale = 0.05},
        {recipe = "kr-superior-transport-belt", scale = 0.05},
        {recipe = "kr-superior-underground-belt", scale = 0.05},
        {recipe = "se-deep-space-splitter-black", scale = 0.05},
        {recipe = "se-deep-space-splitter-blue", scale = 0.05},
        {recipe = "se-deep-space-splitter-cyan", scale = 0.05},
        {recipe = "se-deep-space-splitter-green", scale = 0.05},
        {recipe = "se-deep-space-splitter-magenta", scale = 0.05},
        {recipe = "se-deep-space-splitter-red", scale = 0.05},
        {recipe = "se-deep-space-splitter-white", scale = 0.05},
        {recipe = "se-deep-space-splitter-yellow", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-black", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-blue", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-cyan", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-green", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-magenta", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-red", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-white", scale = 0.05},
        {recipe = "se-deep-space-transport-belt-yellow", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-black", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-blue", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-cyan", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-green", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-magenta", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-red", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-white", scale = 0.05},
        {recipe = "se-deep-space-underground-belt-yellow", scale = 0.05},
        {recipe = "se-space-splitter", scale = 0.05},
        {recipe = "se-space-transport-belt", scale = 0.05},
        {recipe = "se-space-underground-belt", scale = 0.05}
      },
      icons = {
        {icon = "__Krastorio2Assets__/technologies/logistics-1.png", icon_size = 256},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_character_mining_speed = {
      icons = {
        {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png", icon_size = 256},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-mining.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_character_reach = {
      icons = {
        {icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png", icon_size = 256},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-range.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_copper = {
      effects = {
        {recipe = "copper-plate", scale = 1},
        {recipe = "kr-copper-plate-from-enriched-copper", scale = 1},
        {recipe = "kr-matter-to-copper-plate", scale = 1},
        {recipe = "se-copper-ingot-to-plate", scale = 1}
      },
      icons = {
        {icon = "__Krastorio2Assets__/icons/items/copper-plate.png", icon_size = 64},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_heavy_ammo = {
      effects = {
        {recipe = "cannon-shell", scale = 1},
        {recipe = "explosive-cannon-shell", scale = 0.5},
        {recipe = "explosive-uranium-cannon-shell", scale = 0.2},
        {recipe = "uranium-cannon-shell", scale = 0.2},
        {recipe = "artillery-shell", scale = 0.1},
        {recipe = "kr-antimatter-artillery-shell", scale = 0.1},
        {recipe = "kr-nuclear-artillery-shell", scale = 0.1},
        {recipe = "se-railgun-ammo", scale = 0.1}
      }
    },
    research_inserters = {
      effects = {
        {recipe = "burner-inserter", scale = 1},
        {recipe = "inserter", scale = 1},
        {recipe = "fast-inserter", scale = 0.5},
        {recipe = "long-handed-inserter", scale = 0.5},
        {recipe = "bulk-inserter", scale = 0.2},
        {recipe = "kr-superior-inserter", scale = 0.1},
        {recipe = "kr-superior-long-inserter", scale = 0.1}
      }
    },
    research_iron = {
      effects = {
        {recipe = "iron-plate", scale = 1},
        {recipe = "kr-iron-plate-from-enriched-iron", scale = 1},
        {recipe = "kr-matter-to-iron-plate", scale = 1},
        {recipe = "se-iron-ingot-to-plate", scale = 1}
      },
      icons = {
        {icon = "__Krastorio2Assets__/icons/items/iron-plate.png", icon_size = 64},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_lab_productivity = {
      icons = {
        {icon = "__Krastorio2Assets__/technologies/military-tech-card.png", icon_size = 256},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_landfill = {
      effects = {
        {recipe = "kr-landfill-with-sand", scale = 1},
        {recipe = "landfill", scale = 1},
        {recipe = "landfill-copper-ore", scale = 1},
        {recipe = "landfill-iron-ore", scale = 1},
        {recipe = "landfill-kr-rare-metal-ore", scale = 1},
        {recipe = "landfill-sand", scale = 1},
        {recipe = "landfill-se-beryllium-ore", scale = 1},
        {recipe = "landfill-se-holmium-ore", scale = 1},
        {recipe = "landfill-se-iridium-ore", scale = 1}
      }
    },
    research_mining_drill = {
      effects = {
        {recipe = "burner-mining-drill", scale = 1},
        {recipe = "electric-mining-drill", scale = 0.5},
        {recipe = "area-mining-drill", scale = 0.25},
        {recipe = "kr-quarry-drill", scale = 0.25},
        {recipe = "se-core-miner-drill", scale = 0.25}
      },
      icons = {
        {icon = "__Krastorio2Assets__/icons/entities/electric-mining-drill.png", icon_size = 64},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_rocket_fuel = {
      effects = {
        {recipe = "kr-rocket-fuel-with-ammonia", scale = 1},
        {recipe = "kr-rocket-fuel-with-hydrogen-chloride", scale = 1},
        {recipe = "rocket-fuel", scale = 1},
        {recipe = "se-vulcanite-rocket-fuel", scale = 1}
      }
    },
    research_science_pack_productivity = {
      effects = {
        {recipe = "automation-science-pack", scale = 1},
        {recipe = "chemical-science-pack", scale = 1},
        {recipe = "kr-basic-tech-card", scale = 1},
        {recipe = "kr-matter-tech-card", scale = 1},
        {recipe = "kr-optimization-tech-card", scale = 1},
        {recipe = "logistic-science-pack", scale = 1},
        {recipe = "military-science-pack", scale = 1},
        {recipe = "production-science-pack", scale = 1},
        {recipe = "se-astronomic-science-pack-1", scale = 1},
        {recipe = "se-astronomic-science-pack-2", scale = 1},
        {recipe = "se-astronomic-science-pack-3", scale = 1},
        {recipe = "se-astronomic-science-pack-4", scale = 1},
        {recipe = "se-biological-science-pack-1", scale = 1},
        {recipe = "se-biological-science-pack-2", scale = 1},
        {recipe = "se-biological-science-pack-3", scale = 1},
        {recipe = "se-biological-science-pack-4", scale = 1},
        {recipe = "se-deep-space-science-pack-1", scale = 1},
        {recipe = "se-deep-space-science-pack-2", scale = 1},
        {recipe = "se-deep-space-science-pack-3", scale = 1},
        {recipe = "se-deep-space-science-pack-4", scale = 1},
        {recipe = "se-energy-science-pack-1", scale = 1},
        {recipe = "se-energy-science-pack-2", scale = 1},
        {recipe = "se-energy-science-pack-3", scale = 1},
        {recipe = "se-energy-science-pack-4", scale = 1},
        {recipe = "se-kr-matter-science-pack-2", scale = 1},
        {recipe = "se-material-science-pack-1", scale = 1},
        {recipe = "se-material-science-pack-2", scale = 1},
        {recipe = "se-material-science-pack-3", scale = 1},
        {recipe = "se-material-science-pack-4", scale = 1},
        {recipe = "se-rocket-science-pack", scale = 1},
        {recipe = "space-science-pack", scale = 1},
        {recipe = "utility-science-pack", scale = 1}
      },
      prerequisites = {"kr-singularity-tech-card", "se-deep-space-science-pack-4"},
      science = "science_se_k2_research_science_pack_productivity"
    },
    research_steel = {
      icons = {
        {icon = "__Krastorio2Assets__/technologies/steel-processing.png", icon_size = 256},
        {
          floating = true,
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50}
        }
      }
    },
    research_sulfur = {
      effects = {
        {recipe = "kr-imersite-crystal", scale = 1},
        {recipe = "kr-imersium-plate", scale = 1},
        {recipe = "kr-matter-to-sulfur", scale = 1},
        {recipe = "sulfur", scale = 1}
      }
    }
  },
  exact_product_bindings = {
    {
      allow_shared_input_output = true,
      family = "research_belts",
      include_recycling = true,
      recipes = {"splitter", "transport-belt", "underground-belt"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_belts",
      include_recycling = true,
      recipes = {"fast-splitter", "fast-transport-belt", "fast-underground-belt", "kr-fast-loader"},
      reject_explicit_productivity_denial = true,
      weight = 0.5
    },
    {
      allow_shared_input_output = true,
      family = "research_belts",
      include_recycling = true,
      recipes = {"express-splitter", "express-transport-belt", "express-underground-belt", "kr-express-loader"},
      reject_explicit_productivity_denial = true,
      weight = 0.2
    },
    {
      allow_shared_input_output = true,
      family = "research_belts",
      include_recycling = true,
      recipes = {
        "kr-advanced-loader",
        "kr-advanced-splitter",
        "kr-advanced-transport-belt",
        "kr-advanced-underground-belt",
        "kr-loader",
        "kr-se-deep-space-loader-black",
        "kr-se-loader",
        "kr-superior-loader",
        "kr-superior-splitter",
        "kr-superior-transport-belt",
        "kr-superior-underground-belt",
        "se-deep-space-splitter-black",
        "se-deep-space-splitter-blue",
        "se-deep-space-splitter-cyan",
        "se-deep-space-splitter-green",
        "se-deep-space-splitter-magenta",
        "se-deep-space-splitter-red",
        "se-deep-space-splitter-white",
        "se-deep-space-splitter-yellow",
        "se-deep-space-transport-belt-black",
        "se-deep-space-transport-belt-blue",
        "se-deep-space-transport-belt-cyan",
        "se-deep-space-transport-belt-green",
        "se-deep-space-transport-belt-magenta",
        "se-deep-space-transport-belt-red",
        "se-deep-space-transport-belt-white",
        "se-deep-space-transport-belt-yellow",
        "se-deep-space-underground-belt-black",
        "se-deep-space-underground-belt-blue",
        "se-deep-space-underground-belt-cyan",
        "se-deep-space-underground-belt-green",
        "se-deep-space-underground-belt-magenta",
        "se-deep-space-underground-belt-red",
        "se-deep-space-underground-belt-white",
        "se-deep-space-underground-belt-yellow",
        "se-space-splitter",
        "se-space-transport-belt",
        "se-space-underground-belt"
      },
      reject_explicit_productivity_denial = true,
      weight = 0.05
    },
    {
      allow_shared_input_output = true,
      family = "research_copper",
      include_recycling = true,
      recipes = {
        "copper-plate",
        "kr-copper-plate-from-enriched-copper",
        "kr-matter-to-copper-plate",
        "se-copper-ingot-to-plate"
      },
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_gears",
      include_recycling = true,
      recipes = {"iron-gear-wheel"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_heavy_ammo",
      include_recycling = true,
      recipes = {"cannon-shell"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_heavy_ammo",
      include_recycling = true,
      recipes = {"explosive-cannon-shell"},
      reject_explicit_productivity_denial = true,
      weight = 0.5
    },
    {
      allow_shared_input_output = true,
      family = "research_heavy_ammo",
      include_recycling = true,
      recipes = {"explosive-uranium-cannon-shell", "uranium-cannon-shell"},
      reject_explicit_productivity_denial = true,
      weight = 0.2
    },
    {
      allow_shared_input_output = true,
      family = "research_heavy_ammo",
      include_recycling = true,
      recipes = {"artillery-shell", "kr-antimatter-artillery-shell", "kr-nuclear-artillery-shell", "se-railgun-ammo"},
      reject_explicit_productivity_denial = true,
      weight = 0.1
    },
    {
      allow_shared_input_output = true,
      family = "research_inserters",
      include_recycling = true,
      recipes = {"burner-inserter", "inserter"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_inserters",
      include_recycling = true,
      recipes = {"fast-inserter", "long-handed-inserter"},
      reject_explicit_productivity_denial = true,
      weight = 0.5
    },
    {
      allow_shared_input_output = true,
      family = "research_inserters",
      include_recycling = true,
      recipes = {"bulk-inserter"},
      reject_explicit_productivity_denial = true,
      weight = 0.2
    },
    {
      allow_shared_input_output = true,
      family = "research_inserters",
      include_recycling = true,
      recipes = {"kr-superior-inserter", "kr-superior-long-inserter"},
      reject_explicit_productivity_denial = true,
      weight = 0.1
    },
    {
      allow_shared_input_output = true,
      family = "research_iron",
      include_recycling = true,
      recipes = {"iron-plate", "kr-iron-plate-from-enriched-iron", "kr-matter-to-iron-plate", "se-iron-ingot-to-plate"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_landfill",
      include_recycling = true,
      recipes = {
        "kr-landfill-with-sand",
        "landfill",
        "landfill-copper-ore",
        "landfill-iron-ore",
        "landfill-kr-rare-metal-ore",
        "landfill-sand",
        "landfill-se-beryllium-ore",
        "landfill-se-holmium-ore",
        "landfill-se-iridium-ore"
      },
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_mining_drill",
      include_recycling = true,
      recipes = {"burner-mining-drill"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_mining_drill",
      include_recycling = true,
      recipes = {"electric-mining-drill"},
      reject_explicit_productivity_denial = true,
      weight = 0.5
    },
    {
      allow_shared_input_output = true,
      family = "research_mining_drill",
      include_recycling = true,
      recipes = {"area-mining-drill", "kr-quarry-drill", "se-core-miner-drill"},
      reject_explicit_productivity_denial = true,
      weight = 0.25
    },
    {
      allow_shared_input_output = true,
      family = "research_rocket_fuel",
      include_recycling = true,
      recipes = {
        "kr-rocket-fuel-with-ammonia",
        "kr-rocket-fuel-with-hydrogen-chloride",
        "rocket-fuel",
        "se-vulcanite-rocket-fuel"
      },
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_science_pack_productivity",
      include_recycling = true,
      recipes = {
        "automation-science-pack",
        "chemical-science-pack",
        "kr-basic-tech-card",
        "kr-matter-tech-card",
        "kr-optimization-tech-card",
        "logistic-science-pack",
        "military-science-pack",
        "production-science-pack",
        "se-astronomic-science-pack-1",
        "se-astronomic-science-pack-2",
        "se-astronomic-science-pack-3",
        "se-astronomic-science-pack-4",
        "se-biological-science-pack-1",
        "se-biological-science-pack-2",
        "se-biological-science-pack-3",
        "se-biological-science-pack-4",
        "se-deep-space-science-pack-1",
        "se-deep-space-science-pack-2",
        "se-deep-space-science-pack-3",
        "se-deep-space-science-pack-4",
        "se-energy-science-pack-1",
        "se-energy-science-pack-2",
        "se-energy-science-pack-3",
        "se-energy-science-pack-4",
        "se-kr-matter-science-pack-2",
        "se-material-science-pack-1",
        "se-material-science-pack-2",
        "se-material-science-pack-3",
        "se-material-science-pack-4",
        "se-rocket-science-pack",
        "space-science-pack",
        "utility-science-pack"
      },
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_steel",
      include_recycling = true,
      recipes = {"steel-plate"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_sulfur",
      include_recycling = true,
      recipes = {"kr-imersite-crystal", "kr-imersium-plate", "kr-matter-to-sulfur", "sulfur"},
      reject_explicit_productivity_denial = true,
      weight = 1
    },
    {
      allow_shared_input_output = true,
      family = "research_plastic",
      include_recycling = true,
      recipes = {"plastic-bar"},
      reject_explicit_productivity_denial = true,
      weight = 1
    }
  },
  exact_product_target_families = {
    research_belts = true,
    research_copper = true,
    research_gears = true,
    research_heavy_ammo = true,
    research_inserters = true,
    research_iron = true,
    research_landfill = true,
    research_mining_drill = true,
    research_plastic = true,
    research_rocket_fuel = true,
    research_science_pack_productivity = true,
    research_steel = true,
    research_sulfur = true
  },
  excluded_product_target_recipes = {},
  replacement_product_target_families = {},
  required_product_targets = {
    research_belts = {
      "express-splitter",
      "express-transport-belt",
      "express-underground-belt",
      "fast-splitter",
      "fast-transport-belt",
      "fast-underground-belt",
      "kr-advanced-loader",
      "kr-advanced-splitter",
      "kr-advanced-transport-belt",
      "kr-advanced-underground-belt",
      "kr-express-loader",
      "kr-fast-loader",
      "kr-loader",
      "kr-se-deep-space-loader-black",
      "kr-se-loader",
      "kr-superior-loader",
      "kr-superior-splitter",
      "kr-superior-transport-belt",
      "kr-superior-underground-belt",
      "se-deep-space-splitter-black",
      "se-deep-space-splitter-blue",
      "se-deep-space-splitter-cyan",
      "se-deep-space-splitter-green",
      "se-deep-space-splitter-magenta",
      "se-deep-space-splitter-red",
      "se-deep-space-splitter-white",
      "se-deep-space-splitter-yellow",
      "se-deep-space-transport-belt-black",
      "se-deep-space-transport-belt-blue",
      "se-deep-space-transport-belt-cyan",
      "se-deep-space-transport-belt-green",
      "se-deep-space-transport-belt-magenta",
      "se-deep-space-transport-belt-red",
      "se-deep-space-transport-belt-white",
      "se-deep-space-transport-belt-yellow",
      "se-deep-space-underground-belt-black",
      "se-deep-space-underground-belt-blue",
      "se-deep-space-underground-belt-cyan",
      "se-deep-space-underground-belt-green",
      "se-deep-space-underground-belt-magenta",
      "se-deep-space-underground-belt-red",
      "se-deep-space-underground-belt-white",
      "se-deep-space-underground-belt-yellow",
      "se-space-splitter",
      "se-space-transport-belt",
      "se-space-underground-belt",
      "splitter",
      "transport-belt",
      "underground-belt"
    },
    research_copper = {
      "copper-plate",
      "kr-copper-plate-from-enriched-copper",
      "kr-matter-to-copper-plate",
      "se-copper-ingot-to-plate"
    },
    research_gears = {"iron-gear-wheel"},
    research_heavy_ammo = {
      "artillery-shell",
      "cannon-shell",
      "explosive-cannon-shell",
      "explosive-uranium-cannon-shell",
      "kr-antimatter-artillery-shell",
      "kr-nuclear-artillery-shell",
      "se-railgun-ammo",
      "uranium-cannon-shell"
    },
    research_inserters = {
      "bulk-inserter",
      "burner-inserter",
      "fast-inserter",
      "inserter",
      "kr-superior-inserter",
      "kr-superior-long-inserter",
      "long-handed-inserter"
    },
    research_iron = {"iron-plate", "kr-iron-plate-from-enriched-iron", "kr-matter-to-iron-plate", "se-iron-ingot-to-plate"},
    research_landfill = {
      "kr-landfill-with-sand",
      "landfill",
      "landfill-copper-ore",
      "landfill-iron-ore",
      "landfill-kr-rare-metal-ore",
      "landfill-sand",
      "landfill-se-beryllium-ore",
      "landfill-se-holmium-ore",
      "landfill-se-iridium-ore"
    },
    research_mining_drill = {
      "area-mining-drill",
      "burner-mining-drill",
      "electric-mining-drill",
      "kr-quarry-drill",
      "se-core-miner-drill"
    },
    research_plastic = {"plastic-bar"},
    research_rocket_fuel = {
      "kr-rocket-fuel-with-ammonia",
      "kr-rocket-fuel-with-hydrogen-chloride",
      "rocket-fuel",
      "se-vulcanite-rocket-fuel"
    },
    research_science_pack_productivity = {
      "automation-science-pack",
      "chemical-science-pack",
      "kr-basic-tech-card",
      "kr-matter-tech-card",
      "kr-optimization-tech-card",
      "logistic-science-pack",
      "military-science-pack",
      "production-science-pack",
      "se-astronomic-science-pack-1",
      "se-astronomic-science-pack-2",
      "se-astronomic-science-pack-3",
      "se-astronomic-science-pack-4",
      "se-biological-science-pack-1",
      "se-biological-science-pack-2",
      "se-biological-science-pack-3",
      "se-biological-science-pack-4",
      "se-deep-space-science-pack-1",
      "se-deep-space-science-pack-2",
      "se-deep-space-science-pack-3",
      "se-deep-space-science-pack-4",
      "se-energy-science-pack-1",
      "se-energy-science-pack-2",
      "se-energy-science-pack-3",
      "se-energy-science-pack-4",
      "se-kr-matter-science-pack-2",
      "se-material-science-pack-1",
      "se-material-science-pack-2",
      "se-material-science-pack-3",
      "se-material-science-pack-4",
      "se-rocket-science-pack",
      "space-science-pack",
      "utility-science-pack"
    },
    research_steel = {"steel-plate"},
    research_sulfur = {"kr-imersite-crystal", "kr-imersium-plate", "kr-matter-to-sulfur", "sulfur"}
  },
  science = {
    science_se_k2_inserter_capacity_bonus = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-material-science-pack-2",
      "utility-science-pack",
      "kr-optimization-tech-card",
      "se-astronomic-science-pack-2"
    },
    science_se_k2_research_science_pack_productivity = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "space-science-pack",
      "kr-advanced-tech-card",
      "kr-basic-tech-card",
      "kr-matter-tech-card",
      "kr-optimization-tech-card",
      "kr-singularity-tech-card",
      "se-astronomic-science-pack-1",
      "se-astronomic-science-pack-2",
      "se-astronomic-science-pack-3",
      "se-astronomic-science-pack-4",
      "se-biological-science-pack-1",
      "se-biological-science-pack-2",
      "se-biological-science-pack-3",
      "se-biological-science-pack-4",
      "se-deep-space-science-pack-1",
      "se-deep-space-science-pack-2",
      "se-deep-space-science-pack-3",
      "se-deep-space-science-pack-4",
      "se-energy-science-pack-1",
      "se-energy-science-pack-2",
      "se-energy-science-pack-3",
      "se-energy-science-pack-4",
      "se-kr-matter-science-pack-2",
      "se-material-science-pack-1",
      "se-material-science-pack-2",
      "se-material-science-pack-3",
      "se-material-science-pack-4",
      "se-rocket-science-pack"
    },
    science_se_k2_research_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-energy-science-pack-1",
      "kr-optimization-tech-card",
      "production-science-pack",
      "se-material-science-pack-1",
      "se-astronomic-science-pack-1",
      "se-biological-science-pack-1",
      "military-science-pack",
      "kr-advanced-tech-card",
      "kr-basic-tech-card",
      "kr-matter-tech-card",
      "kr-singularity-tech-card",
      "se-astronomic-science-pack-2",
      "se-astronomic-science-pack-3",
      "se-astronomic-science-pack-4",
      "se-biological-science-pack-2",
      "se-biological-science-pack-3",
      "se-biological-science-pack-4",
      "se-deep-space-science-pack-1",
      "se-deep-space-science-pack-2",
      "se-deep-space-science-pack-3",
      "se-deep-space-science-pack-4",
      "se-energy-science-pack-2",
      "se-energy-science-pack-3",
      "se-energy-science-pack-4",
      "se-kr-matter-science-pack-2",
      "se-material-science-pack-2",
      "se-material-science-pack-3",
      "se-material-science-pack-4"
    },
    science_se_k2_worker_robots_storage = {
      "production-science-pack",
      "kr-optimization-tech-card",
      "se-rocket-science-pack",
      "se-material-science-pack-1",
      "space-science-pack",
      "chemical-science-pack"
    }
  }
}
