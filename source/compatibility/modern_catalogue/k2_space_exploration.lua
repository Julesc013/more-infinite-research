-- Exact published F210 Krastorio 2 plus Space Exploration overlay.
-- Captured rows are literal named inputs: this module does not inspect mod graphs,
-- enumerate recipes, or mutate prototypes. Shared composition is owned by modern_catalogue.lua.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function effect(recipe, scale)
  return {recipe = recipe, scale = scale or 1}
end

local function direct_effect(type_name, scale, ammo_category)
  local row = {type = type_name, scale = scale, raw = false}
  if ammo_category then row.ammo_category = ammo_category end
  return row
end

local function exact_binding(family, weight, recipes)
  return {family=family, weight=weight, recipes=recipes, include_recycling=true,
    allow_shared_input_output=true, reject_explicit_productivity_denial=true}
end

return {
  captured_source_data_raw_dump_sha256 = "95953A89CA8B03AEEB481219228DBBDC020EE1361CB0A646D39B8C99E5ABBCFC",
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
    science_se_k2_laser_shooting_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-energy-science-pack-2"
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
    science_se_k2_weapon_shooting_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-material-science-pack-1",
      "production-science-pack"
    },
    science_se_k2_worker_robots_storage = {
      "production-science-pack",
      "kr-optimization-tech-card",
      "se-rocket-science-pack",
      "se-material-science-pack-1",
      "space-science-pack",
      "chemical-science-pack"
    },
    science_se_k2_research_belts = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_k2_research_character_mining_speed = {
      "utility-science-pack",
      "military-science-pack"
    },
    science_se_k2_research_character_reach = {
      "utility-science-pack",
      "military-science-pack"
    },
    science_se_k2_research_copper = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_k2_research_gears = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_k2_research_heavy_ammo = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
    science_se_k2_research_inserters = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_k2_research_iron = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_k2_research_lab_productivity = {
      "automation-science-pack",
      "logistic-science-pack",
      "military-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "utility-science-pack",
      "space-science-pack"
    },
    science_se_k2_research_landfill = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_k2_research_mining_drill = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_k2_research_rocket_fuel = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
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
    science_se_k2_research_steel = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_k2_research_sulfur = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
  },
  definition_overrides = {
    research_belts = {
      science = "science_se_k2_research_belts",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("splitter"), effect("transport-belt"), effect("underground-belt"), effect("fast-splitter", 0.5), effect("fast-transport-belt", 0.5), effect("fast-underground-belt", 0.5), effect("kr-fast-loader", 0.5), effect("express-splitter", 0.19999999999999998), effect("express-transport-belt", 0.19999999999999998), effect("express-underground-belt", 0.19999999999999998), effect("kr-express-loader", 0.19999999999999998), effect("kr-advanced-loader", 0.049999999999999996), effect("kr-advanced-splitter", 0.049999999999999996), effect("kr-advanced-transport-belt", 0.049999999999999996), effect("kr-advanced-underground-belt", 0.049999999999999996), effect("kr-loader", 0.049999999999999996), effect("kr-se-deep-space-loader-black", 0.049999999999999996), effect("kr-se-loader", 0.049999999999999996), effect("kr-superior-loader", 0.049999999999999996), effect("kr-superior-splitter", 0.049999999999999996), effect("kr-superior-transport-belt", 0.049999999999999996), effect("kr-superior-underground-belt", 0.049999999999999996), effect("se-deep-space-splitter-black", 0.049999999999999996), effect("se-deep-space-splitter-blue", 0.049999999999999996), effect("se-deep-space-splitter-cyan", 0.049999999999999996), effect("se-deep-space-splitter-green", 0.049999999999999996), effect("se-deep-space-splitter-magenta", 0.049999999999999996), effect("se-deep-space-splitter-red", 0.049999999999999996), effect("se-deep-space-splitter-white", 0.049999999999999996), effect("se-deep-space-splitter-yellow", 0.049999999999999996), effect("se-deep-space-transport-belt-black", 0.049999999999999996), effect("se-deep-space-transport-belt-blue", 0.049999999999999996), effect("se-deep-space-transport-belt-cyan", 0.049999999999999996), effect("se-deep-space-transport-belt-green", 0.049999999999999996), effect("se-deep-space-transport-belt-magenta", 0.049999999999999996), effect("se-deep-space-transport-belt-red", 0.049999999999999996), effect("se-deep-space-transport-belt-white", 0.049999999999999996), effect("se-deep-space-transport-belt-yellow", 0.049999999999999996), effect("se-deep-space-underground-belt-black", 0.049999999999999996), effect("se-deep-space-underground-belt-blue", 0.049999999999999996), effect("se-deep-space-underground-belt-cyan", 0.049999999999999996), effect("se-deep-space-underground-belt-green", 0.049999999999999996), effect("se-deep-space-underground-belt-magenta", 0.049999999999999996), effect("se-deep-space-underground-belt-red", 0.049999999999999996), effect("se-deep-space-underground-belt-white", 0.049999999999999996), effect("se-deep-space-underground-belt-yellow", 0.049999999999999996), effect("se-space-splitter", 0.049999999999999996), effect("se-space-transport-belt", 0.049999999999999996), effect("se-space-underground-belt", 0.049999999999999996)},
      icons = {
        {
          icon = "__Krastorio2Assets__/technologies/logistics-1.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_character_mining_speed = {
      science = "science_se_k2_research_character_mining_speed",
      prerequisites = {
        "utility-science-pack",
        "military-science-pack"
      },
      effects = {direct_effect("character-mining-speed", 0.5)},
      icons = {
        {
          icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-mining.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_character_reach = {
      science = "science_se_k2_research_character_reach",
      prerequisites = {
        "utility-science-pack",
        "military-science-pack"
      },
      effects = {direct_effect("character-reach-distance", 100.0), direct_effect("character-build-distance", 100.0), direct_effect("character-resource-reach-distance", 100.0), direct_effect("character-item-drop-distance", 100.0)},
      icons = {
        {
          icon = "__Krastorio2Assets__/technologies/steel-pickaxe.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-range.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_copper = {
      science = "science_se_k2_research_copper",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("copper-plate"), effect("kr-copper-plate-from-enriched-copper"), effect("kr-matter-to-copper-plate"), effect("se-copper-ingot-to-plate")},
      icons = {
        {
          icon = "__Krastorio2Assets__/icons/items/copper-plate.png",
          icon_size = 64
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_gears = {
      science = "science_se_k2_research_gears",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("iron-gear-wheel")},
      icons = {
        {
          icon = "__Krastorio2Assets__/icons/items/iron-gear-wheel.png",
          icon_size = 64
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_heavy_ammo = {
      science = "science_se_k2_research_heavy_ammo",
      prerequisites = {
        "production-science-pack",
        "military-science-pack"
      },
      effects = {effect("cannon-shell"), effect("explosive-cannon-shell", 0.5), effect("explosive-uranium-cannon-shell", 0.19999999999999998), effect("uranium-cannon-shell", 0.19999999999999998), effect("artillery-shell", 0.09999999999999999), effect("kr-antimatter-artillery-shell", 0.09999999999999999), effect("kr-nuclear-artillery-shell", 0.09999999999999999), effect("se-railgun-ammo", 0.09999999999999999)},
      icons = {
        {
          icon = "__base__/graphics/icons/cannon-shell.png",
          icon_size = 64
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_inserters = {
      science = "science_se_k2_research_inserters",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("burner-inserter"), effect("inserter"), effect("fast-inserter", 0.5), effect("long-handed-inserter", 0.5), effect("bulk-inserter", 0.19999999999999998), effect("kr-superior-inserter", 0.09999999999999999), effect("kr-superior-long-inserter", 0.09999999999999999)},
      icons = {
        {
          icon = "__base__/graphics/technology/fast-inserter.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_iron = {
      science = "science_se_k2_research_iron",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("iron-plate"), effect("kr-iron-plate-from-enriched-iron"), effect("kr-matter-to-iron-plate"), effect("se-iron-ingot-to-plate")},
      icons = {
        {
          icon = "__Krastorio2Assets__/icons/items/iron-plate.png",
          icon_size = 64
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_lab_productivity = {
      science = "science_se_k2_research_lab_productivity",
      prerequisites = {
        "military-science-pack",
        "production-science-pack",
        "utility-science-pack"
      },
      effects = {direct_effect("laboratory-productivity", 1.0)},
      icons = {
        {
          icon = "__Krastorio2Assets__/technologies/military-tech-card.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_landfill = {
      science = "science_se_k2_research_landfill",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("kr-landfill-with-sand"), effect("landfill"), effect("landfill-copper-ore"), effect("landfill-iron-ore"), effect("landfill-kr-rare-metal-ore"), effect("landfill-sand"), effect("landfill-se-beryllium-ore"), effect("landfill-se-holmium-ore"), effect("landfill-se-iridium-ore")},
      icons = {
        {
          icon = "__base__/graphics/technology/landfill.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_mining_drill = {
      science = "science_se_k2_research_mining_drill",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("burner-mining-drill", 2.0), effect("electric-mining-drill"), effect("area-mining-drill", 0.5), effect("kr-quarry-drill", 0.5), effect("se-core-miner-drill", 0.5)},
      icons = {
        {
          icon = "__Krastorio2Assets__/icons/entities/electric-mining-drill.png",
          icon_size = 64
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_rocket_fuel = {
      science = "science_se_k2_research_rocket_fuel",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("kr-rocket-fuel-with-ammonia"), effect("kr-rocket-fuel-with-hydrogen-chloride"), effect("rocket-fuel"), effect("se-vulcanite-rocket-fuel")},
      icons = {
        {
          icon = "__base__/graphics/technology/rocket-fuel.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_science_pack_productivity = {
      science = "science_se_k2_research_science_pack_productivity",
      prerequisites = {
        "kr-singularity-tech-card",
        "se-deep-space-science-pack-4"
      },
      effects = {effect("automation-science-pack"), effect("chemical-science-pack"), effect("kr-basic-tech-card"), effect("kr-matter-tech-card"), effect("kr-optimization-tech-card"), effect("logistic-science-pack"), effect("military-science-pack"), effect("production-science-pack"), effect("se-astronomic-science-pack-1"), effect("se-astronomic-science-pack-2"), effect("se-astronomic-science-pack-3"), effect("se-astronomic-science-pack-4"), effect("se-biological-science-pack-1"), effect("se-biological-science-pack-2"), effect("se-biological-science-pack-3"), effect("se-biological-science-pack-4"), effect("se-deep-space-science-pack-1"), effect("se-deep-space-science-pack-2"), effect("se-deep-space-science-pack-3"), effect("se-deep-space-science-pack-4"), effect("se-energy-science-pack-1"), effect("se-energy-science-pack-2"), effect("se-energy-science-pack-3"), effect("se-energy-science-pack-4"), effect("se-kr-matter-science-pack-2"), effect("se-material-science-pack-1"), effect("se-material-science-pack-2"), effect("se-material-science-pack-3"), effect("se-material-science-pack-4"), effect("se-rocket-science-pack"), effect("space-science-pack"), effect("utility-science-pack")},
      icons = {
        {
          icon = "__space-exploration-graphics__/graphics/technology/catalogue/deep-1.png",
          icon_size = 128
        },
        {
          icon = "__space-exploration-graphics__/graphics/technology/catalogue/mask-1.png",
          icon_size = 128
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_steel = {
      science = "science_se_k2_research_steel",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("steel-plate")},
      icons = {
        {
          icon = "__Krastorio2Assets__/technologies/steel-processing.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
    research_sulfur = {
      science = "science_se_k2_research_sulfur",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("kr-imersite-crystal"), effect("kr-imersium-plate"), effect("kr-matter-to-sulfur"), effect("sulfur")},
      icons = {
        {
          icon = "__base__/graphics/technology/sulfur-processing.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
          icon_size = 128,
          scale = 0.5,
          shift = {
            50,
            50
          },
          floating = true
        }
      },
    },
  },
  additions = {},
  continuation_overrides = {
    inserter_capacity_bonus = {science="science_se_k2_inserter_capacity_bonus", prerequisites={
        "inserter-capacity-bonus-7"
      }, effects={direct_effect("inserter-stack-size-bonus", 0.5), direct_effect("bulk-inserter-capacity-bonus", 1.0)}},
    laser_shooting_speed = {science="science_se_k2_laser_shooting_speed", prerequisites={
        "laser-shooting-speed-7"
      }, effects={direct_effect("gun-speed", 0.2, "laser"), direct_effect("gun-speed", 1.0, "cryogun"), direct_effect("gun-speed", 0.2, "kr-impulse-rifle")}},
    research_speed = {science="science_se_k2_research_speed", prerequisites={
        "research-speed-6",
        "kr-singularity-tech-card",
        "se-deep-space-science-pack-4"
      }, effects={direct_effect("laboratory-speed", 1.0)}},
    weapon_shooting_speed = {science="science_se_k2_weapon_shooting_speed", prerequisites={
        "weapon-shooting-speed-6"
      }, effects={direct_effect("gun-speed", 0.375, "bullet"), direct_effect("gun-speed", 0.375, "shotgun-shell"), direct_effect("gun-speed", 1.25, "railgun"), direct_effect("gun-speed", 0.375, "kr-pistol"), direct_effect("gun-speed", 0.375, "kr-anti-materiel-rifle-ammo"), direct_effect("gun-speed", 0.5, "kr-railgun-shell"), direct_effect("gun-speed", 0.5, "kr-turret-missile"), direct_effect("gun-speed", 0.5, "kr-heavy-rocket")}},
    worker_robots_storage = {science="science_se_k2_worker_robots_storage", prerequisites={
        "worker-robots-storage-3"
      }, effects={direct_effect("worker-robot-storage", 1.0)}},
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
    research_rocket_fuel = true,
    research_science_pack_productivity = true,
    research_steel = true,
    research_sulfur = true
  },
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
    research_gears = {
      "iron-gear-wheel"
    },
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
    research_iron = {
      "iron-plate",
      "kr-iron-plate-from-enriched-iron",
      "kr-matter-to-iron-plate",
      "se-iron-ingot-to-plate"
    },
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
    research_steel = {
      "steel-plate"
    },
    research_sulfur = {
      "kr-imersite-crystal",
      "kr-imersium-plate",
      "kr-matter-to-sulfur",
      "sulfur"
    }
  },
  exact_product_bindings = {
    exact_binding("research_belts", 1.0, {
      "splitter",
      "transport-belt",
      "underground-belt"
    }),
    exact_binding("research_belts", 0.5, {
      "fast-splitter",
      "fast-transport-belt",
      "fast-underground-belt",
      "kr-fast-loader"
    }),
    exact_binding("research_belts", 0.19999999999999998, {
      "express-splitter",
      "express-transport-belt",
      "express-underground-belt",
      "kr-express-loader"
    }),
    exact_binding("research_belts", 0.049999999999999996, {
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
    }),
    exact_binding("research_copper", 1.0, {
      "copper-plate",
      "kr-copper-plate-from-enriched-copper",
      "kr-matter-to-copper-plate",
      "se-copper-ingot-to-plate"
    }),
    exact_binding("research_gears", 1.0, {
      "iron-gear-wheel"
    }),
    exact_binding("research_heavy_ammo", 1.0, {
      "cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.5, {
      "explosive-cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.19999999999999998, {
      "explosive-uranium-cannon-shell",
      "uranium-cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.09999999999999999, {
      "artillery-shell",
      "kr-antimatter-artillery-shell",
      "kr-nuclear-artillery-shell",
      "se-railgun-ammo"
    }),
    exact_binding("research_inserters", 1.0, {
      "burner-inserter",
      "inserter"
    }),
    exact_binding("research_inserters", 0.5, {
      "fast-inserter",
      "long-handed-inserter"
    }),
    exact_binding("research_inserters", 0.19999999999999998, {
      "bulk-inserter"
    }),
    exact_binding("research_inserters", 0.09999999999999999, {
      "kr-superior-inserter",
      "kr-superior-long-inserter"
    }),
    exact_binding("research_iron", 1.0, {
      "iron-plate",
      "kr-iron-plate-from-enriched-iron",
      "kr-matter-to-iron-plate",
      "se-iron-ingot-to-plate"
    }),
    exact_binding("research_landfill", 1.0, {
      "kr-landfill-with-sand",
      "landfill",
      "landfill-copper-ore",
      "landfill-iron-ore",
      "landfill-kr-rare-metal-ore",
      "landfill-sand",
      "landfill-se-beryllium-ore",
      "landfill-se-holmium-ore",
      "landfill-se-iridium-ore"
    }),
    exact_binding("research_mining_drill", 2.0, {
      "burner-mining-drill"
    }),
    exact_binding("research_mining_drill", 1.0, {
      "electric-mining-drill"
    }),
    exact_binding("research_mining_drill", 0.5, {
      "area-mining-drill",
      "kr-quarry-drill",
      "se-core-miner-drill"
    }),
    exact_binding("research_rocket_fuel", 1.0, {
      "kr-rocket-fuel-with-ammonia",
      "kr-rocket-fuel-with-hydrogen-chloride",
      "rocket-fuel",
      "se-vulcanite-rocket-fuel"
    }),
    exact_binding("research_science_pack_productivity", 1.0, {
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
    }),
    exact_binding("research_steel", 1.0, {
      "steel-plate"
    }),
    exact_binding("research_sulfur", 1.0, {
      "kr-imersite-crystal",
      "kr-imersium-plate",
      "kr-matter-to-sulfur",
      "sulfur"
    }),
  },
  replacement_product_target_families = {},
  excluded_product_target_recipes = {},
  -- AAI controls the two engine icons; keep those cross-profile facts separate.
  aai_owned_presentation = {"research_engine", "research_electric_engine"},
}
