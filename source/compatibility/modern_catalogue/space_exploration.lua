-- Exact published F210 Space Exploration delta.
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
  science = {
    science_se_braking_force = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-material-science-pack-2"
    },
    science_se_inserter_capacity_bonus = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-material-science-pack-2"
    },
    science_se_laser_shooting_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-energy-science-pack-2"
    },
    science_se_research_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "utility-science-pack",
      "se-rocket-science-pack",
      "space-science-pack",
      "se-energy-science-pack-1",
      "production-science-pack",
      "military-science-pack",
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
      "se-energy-science-pack-2",
      "se-energy-science-pack-3",
      "se-energy-science-pack-4",
      "se-material-science-pack-1",
      "se-material-science-pack-2",
      "se-material-science-pack-3",
      "se-material-science-pack-4"
    },
    science_se_weapon_shooting_speed = {
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
    science_se_worker_robots_storage = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "se-rocket-science-pack",
      "se-material-science-pack-1",
      "space-science-pack"
    },
    science_se_research_belts = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_breeding = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_bullets = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
    science_se_research_concrete = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_copper_cable = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_electric_energy = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_electric_engine = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_electric_shooting_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack"
    },
    science_se_research_electronic_circuit = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_engine = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_flamethrower_shooting_speed = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
    science_se_research_grenades = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
    science_se_research_heavy_ammo = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
    science_se_research_inserters = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_iron = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_iron_sticks = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_lab_productivity = {
      "automation-science-pack",
      "logistic-science-pack",
      "military-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "utility-science-pack",
      "space-science-pack"
    },
    science_se_research_landfill = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_low_density_structure = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_rails = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_robot_battery = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack"
    },
    science_se_research_science_pack_productivity = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "space-science-pack",
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
      "se-material-science-pack-1",
      "se-material-science-pack-2",
      "se-material-science-pack-3",
      "se-material-science-pack-4",
      "se-rocket-science-pack"
    },
    science_se_research_steel = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_sulfuric_acid_productivity = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack"
    },
    science_se_research_walls = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "space-science-pack"
    },
  },
  definition_overrides = {
    research_belts = {
      science = "science_se_research_belts",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("splitter"), effect("transport-belt"), effect("underground-belt"), effect("fast-splitter", 0.5), effect("fast-transport-belt", 0.5), effect("fast-underground-belt", 0.5), effect("express-splitter", 0.2), effect("express-transport-belt", 0.2), effect("express-underground-belt", 0.2), effect("se-deep-space-splitter-black", 0.05), effect("se-deep-space-splitter-blue", 0.05), effect("se-deep-space-splitter-cyan", 0.05), effect("se-deep-space-splitter-green", 0.05), effect("se-deep-space-splitter-magenta", 0.05), effect("se-deep-space-splitter-red", 0.05), effect("se-deep-space-splitter-white", 0.05), effect("se-deep-space-splitter-yellow", 0.05), effect("se-deep-space-transport-belt-black", 0.05), effect("se-deep-space-transport-belt-blue", 0.05), effect("se-deep-space-transport-belt-cyan", 0.05), effect("se-deep-space-transport-belt-green", 0.05), effect("se-deep-space-transport-belt-magenta", 0.05), effect("se-deep-space-transport-belt-red", 0.05), effect("se-deep-space-transport-belt-white", 0.05), effect("se-deep-space-transport-belt-yellow", 0.05), effect("se-deep-space-underground-belt-black", 0.05), effect("se-deep-space-underground-belt-blue", 0.05), effect("se-deep-space-underground-belt-cyan", 0.05), effect("se-deep-space-underground-belt-green", 0.05), effect("se-deep-space-underground-belt-magenta", 0.05), effect("se-deep-space-underground-belt-red", 0.05), effect("se-deep-space-underground-belt-white", 0.05), effect("se-deep-space-underground-belt-yellow", 0.05), effect("se-space-splitter", 0.05), effect("se-space-transport-belt", 0.05), effect("se-space-underground-belt", 0.05)},
      icons = {
        {
          icon = "__base__/graphics/technology/logistics-1.png",
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
    research_bullets = {
      science = "science_se_research_bullets",
      prerequisites = {
        "production-science-pack",
        "military-science-pack"
      },
      effects = {effect("firearm-magazine"), effect("shotgun-shell"), effect("piercing-rounds-magazine", 0.5), effect("piercing-shotgun-shell", 0.5), effect("uranium-rounds-magazine", 0.2)},
      icons = {
        {
          icon = "__base__/graphics/technology/military.png",
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
    research_concrete = {
      science = "science_se_research_concrete",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("se-recycle-radar"), effect("stone-brick"), effect("concrete", 0.5), effect("hazard-concrete", 0.5), effect("se-recycle-big-electric-pole", 0.5), effect("refined-concrete", 0.2), effect("refined-hazard-concrete", 0.2)},
      icons = {
        {
          icon = "__base__/graphics/technology/concrete.png",
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
    research_copper_cable = {
      science = "science_se_research_copper_cable",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("copper-cable"), effect("se-recycle-medium-electric-pole"), effect("se-recycle-small-electric-pole"), effect("se-recycle-small-iron-electric-pole")},
      icons = {
        {
          icon = "__base__/graphics/icons/copper-cable.png",
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
    research_electric_energy = {
      science = "science_se_research_electric_energy",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("accumulator"), effect("se-space-capsule-scorched-scrapping"), effect("se-space-capsule-scrapping"), effect("solar-panel"), effect("se-space-accumulator", 0.5), effect("se-space-solar-panel", 0.5), effect("se-space-accumulator-2", 0.2), effect("se-space-solar-panel-2", 0.2), effect("se-space-solar-panel-3", 0.1)},
      icons = {
        {
          icon = "__base__/graphics/technology/electric-energy-acumulators.png",
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
    research_electric_engine = {
      science = "science_se_research_electric_engine",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("electric-engine-unit")},
    },
    research_electric_shooting_speed = {
      science = "science_se_research_electric_shooting_speed",
      prerequisites = {
        "production-science-pack",
        "discharge-defense-equipment"
      },
      effects = {direct_effect("gun-speed", 1.0, "tesla"), direct_effect("gun-speed", 1.0, "electric")},
      icons = {
        {
          icon = "__base__/graphics/technology/discharge-defense-equipment.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-speed.png",
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
    research_electronic_circuit = {
      science = "science_se_research_electronic_circuit",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("electronic-circuit"), effect("electronic-circuit-wood")},
      icons = {
        {
          icon = "__base__/graphics/technology/electronics.png",
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
    research_engine = {
      science = "science_se_research_engine",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("engine-unit")},
    },
    research_flamethrower_shooting_speed = {
      science = "science_se_research_flamethrower_shooting_speed",
      prerequisites = {
        "production-science-pack",
        "flamethrower"
      },
      effects = {direct_effect("gun-speed", 1.0, "flamethrower")},
      icons = {
        {
          icon = "__base__/graphics/technology/flamethrower.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-speed.png",
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
    research_grenades = {
      science = "science_se_research_grenades",
      prerequisites = {
        "production-science-pack",
        "military-science-pack"
      },
      effects = {effect("grenade"), effect("cluster-grenade", 0.5)},
      icons = {
        {
          icon = "__base__/graphics/icons/grenade.png",
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
      science = "science_se_research_heavy_ammo",
      prerequisites = {
        "production-science-pack",
        "military-science-pack"
      },
      effects = {effect("cannon-shell"), effect("explosive-cannon-shell", 0.5), effect("explosive-uranium-cannon-shell", 0.2), effect("uranium-cannon-shell", 0.2), effect("artillery-shell", 0.1), effect("se-railgun-ammo", 0.1)},
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
      science = "science_se_research_inserters",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("burner-inserter"), effect("inserter"), effect("fast-inserter", 0.5), effect("long-handed-inserter", 0.5), effect("bulk-inserter", 0.2)},
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
      science = "science_se_research_iron",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("iron-plate"), effect("se-iron-ingot-to-plate")},
      icons = {
        {
          icon = "__base__/graphics/icons/iron-plate.png",
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
    research_iron_sticks = {
      science = "science_se_research_iron_sticks",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("iron-stick")},
      icons = {
        {
          icon = "__base__/graphics/icons/iron-stick.png",
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
      science = "science_se_research_lab_productivity",
      prerequisites = {
        "military-science-pack",
        "production-science-pack",
        "utility-science-pack"
      },
      effects = {direct_effect("laboratory-productivity", 1.0)},
      icons = {
        {
          icon = "__base__/graphics/technology/military-science-pack.png",
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
      science = "science_se_research_landfill",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("landfill"), effect("landfill-copper-ore"), effect("landfill-iron-ore"), effect("landfill-sand"), effect("landfill-se-beryllium-ore"), effect("landfill-se-holmium-ore"), effect("landfill-se-iridium-ore")},
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
    research_low_density_structure = {
      science = "science_se_research_low_density_structure",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("low-density-structure"), effect("se-low-density-structure-beryllium")},
      icons = {
        {
          icon = "__base__/graphics/technology/low-density-structure.png",
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
    research_rails = {
      science = "science_se_research_rails",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("rail")},
      icons = {
        {
          icon = "__base__/graphics/icons/rail.png",
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
    research_robot_battery = {
      science = "science_se_research_robot_battery",
      prerequisites = {
        "production-science-pack"
      },
      effects = {direct_effect("worker-robot-battery", 1.0)},
      icons = {
        {
          icon = "__base__/graphics/technology/logistic-robotics.png",
          icon_size = 256
        },
        {
          icon = "__core__/graphics/icons/technology/constants/constant-battery.png",
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
      science = "science_se_research_science_pack_productivity",
      prerequisites = {
        "se-deep-space-science-pack-4"
      },
      effects = {effect("automation-science-pack"), effect("chemical-science-pack"), effect("logistic-science-pack"), effect("military-science-pack"), effect("production-science-pack"), effect("se-astronomic-science-pack-1"), effect("se-astronomic-science-pack-2"), effect("se-astronomic-science-pack-3"), effect("se-astronomic-science-pack-4"), effect("se-biological-science-pack-1"), effect("se-biological-science-pack-2"), effect("se-biological-science-pack-3"), effect("se-biological-science-pack-4"), effect("se-deep-space-science-pack-1"), effect("se-deep-space-science-pack-2"), effect("se-deep-space-science-pack-3"), effect("se-deep-space-science-pack-4"), effect("se-energy-science-pack-1"), effect("se-energy-science-pack-2"), effect("se-energy-science-pack-3"), effect("se-energy-science-pack-4"), effect("se-material-science-pack-1"), effect("se-material-science-pack-2"), effect("se-material-science-pack-3"), effect("se-material-science-pack-4"), effect("se-rocket-science-pack"), effect("space-science-pack"), effect("utility-science-pack")},
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
      science = "science_se_research_steel",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("steel-plate")},
      icons = {
        {
          icon = "__base__/graphics/technology/steel-processing.png",
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
    research_sulfuric_acid_productivity = {
      science = "science_se_research_sulfuric_acid_productivity",
      prerequisites = {
        "production-science-pack"
      },
      effects = {effect("se-naquium-powder"), effect("sulfuric-acid")},
      icons = {
        {
          icon = "__base__/graphics/icons/fluid/sulfuric-acid.png",
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
    research_walls = {
      science = "science_se_research_walls",
      prerequisites = {
        "production-science-pack",
        "military-science-pack"
      },
      effects = {effect("stone-wall"), effect("gate", 0.5)},
      icons = {
        {
          icon = "__base__/graphics/technology/gate.png",
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
  additions = {
    {
      key="research_breeding", family="research_breeding", kind="productivity",
      science="science_se_research_breeding", prerequisites={
        "production-science-pack"
      },
      effects = {effect("se-bioculture"), effect("se-experimental-bioculture"), effect("se-specimen-fish")},
      icons = {
        {
          icon = "__base__/graphics/icons/fish.png",
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
      localised_name = {
        "technology-name.more-infinite-research.research_breeding",
        {
          "technology-name.fish-breeding"
        }
      },
      localised_description = {
        "technology-description.more-infinite-research.recipe_productivity"
      },
      order = "p[research_breeding]",
      tuning = {base_cost=8000, effect_percent=10, enabled=true, growth_factor=2, linear_increment=0, max_level=0, research_time=60},
      setting_order = "b-100-breeding-productivity-stream-research_breeding-",
    },
  },
  continuation_overrides = {
    braking_force = {science="science_se_braking_force", prerequisites={
        "braking-force-7"
      }, effects={direct_effect("train-braking-force-bonus", 1.0)}},
    inserter_capacity_bonus = {science="science_se_inserter_capacity_bonus", prerequisites={
        "inserter-capacity-bonus-7"
      }, effects={direct_effect("inserter-stack-size-bonus", 0.5), direct_effect("bulk-inserter-capacity-bonus", 1.0)}},
    laser_shooting_speed = {science="science_se_laser_shooting_speed", prerequisites={
        "laser-shooting-speed-7"
      }, effects={direct_effect("gun-speed", 1.0, "laser"), direct_effect("gun-speed", 1.0, "cryogun")}},
    research_speed = {science="science_se_research_speed", prerequisites={
        "research-speed-6",
        "se-deep-space-science-pack-4"
      }, effects={direct_effect("laboratory-speed", 1.0)}},
    weapon_shooting_speed = {science="science_se_weapon_shooting_speed", prerequisites={
        "weapon-shooting-speed-6"
      }, effects={direct_effect("gun-speed", 1.0, "bullet"), direct_effect("gun-speed", 1.0, "shotgun-shell"), direct_effect("gun-speed", 1.25, "railgun")}},
    worker_robots_storage = {science="science_se_worker_robots_storage", prerequisites={
        "worker-robots-storage-3"
      }, effects={direct_effect("worker-robot-storage", 1.0)}},
  },
  exact_product_target_families = {
    research_belts = true,
    research_breeding = true,
    research_bullets = true,
    research_concrete = true,
    research_copper_cable = true,
    research_electric_energy = true,
    research_electric_engine = true,
    research_electronic_circuit = true,
    research_engine = true,
    research_grenades = true,
    research_heavy_ammo = true,
    research_inserters = true,
    research_iron = true,
    research_iron_sticks = true,
    research_landfill = true,
    research_low_density_structure = true,
    research_rails = true,
    research_science_pack_productivity = true,
    research_steel = true,
    research_sulfuric_acid_productivity = true,
    research_walls = true
  },
  required_product_targets = {
    research_belts = {
      "express-splitter",
      "express-transport-belt",
      "express-underground-belt",
      "fast-splitter",
      "fast-transport-belt",
      "fast-underground-belt",
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
    research_breeding = {
      "se-bioculture",
      "se-experimental-bioculture",
      "se-specimen-fish"
    },
    research_bullets = {
      "firearm-magazine",
      "piercing-rounds-magazine",
      "piercing-shotgun-shell",
      "shotgun-shell",
      "uranium-rounds-magazine"
    },
    research_concrete = {
      "concrete",
      "hazard-concrete",
      "refined-concrete",
      "refined-hazard-concrete",
      "se-recycle-big-electric-pole",
      "se-recycle-radar",
      "stone-brick"
    },
    research_copper_cable = {
      "copper-cable",
      "se-recycle-medium-electric-pole",
      "se-recycle-small-electric-pole",
      "se-recycle-small-iron-electric-pole"
    },
    research_electric_energy = {
      "accumulator",
      "se-space-accumulator",
      "se-space-accumulator-2",
      "se-space-capsule-scorched-scrapping",
      "se-space-capsule-scrapping",
      "se-space-solar-panel",
      "se-space-solar-panel-2",
      "se-space-solar-panel-3",
      "solar-panel"
    },
    research_electric_engine = {
      "electric-engine-unit"
    },
    research_electronic_circuit = {
      "electronic-circuit",
      "electronic-circuit-wood"
    },
    research_engine = {
      "engine-unit"
    },
    research_grenades = {
      "cluster-grenade",
      "grenade"
    },
    research_heavy_ammo = {
      "artillery-shell",
      "cannon-shell",
      "explosive-cannon-shell",
      "explosive-uranium-cannon-shell",
      "se-railgun-ammo",
      "uranium-cannon-shell"
    },
    research_inserters = {
      "bulk-inserter",
      "burner-inserter",
      "fast-inserter",
      "inserter",
      "long-handed-inserter"
    },
    research_iron = {
      "iron-plate",
      "se-iron-ingot-to-plate"
    },
    research_iron_sticks = {
      "iron-stick"
    },
    research_landfill = {
      "landfill",
      "landfill-copper-ore",
      "landfill-iron-ore",
      "landfill-sand",
      "landfill-se-beryllium-ore",
      "landfill-se-holmium-ore",
      "landfill-se-iridium-ore"
    },
    research_low_density_structure = {
      "low-density-structure",
      "se-low-density-structure-beryllium"
    },
    research_rails = {
      "rail"
    },
    research_science_pack_productivity = {
      "automation-science-pack",
      "chemical-science-pack",
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
    research_sulfuric_acid_productivity = {
      "se-naquium-powder",
      "sulfuric-acid"
    },
    research_walls = {
      "gate",
      "stone-wall"
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
      "fast-underground-belt"
    }),
    exact_binding("research_belts", 0.2, {
      "express-splitter",
      "express-transport-belt",
      "express-underground-belt"
    }),
    exact_binding("research_belts", 0.05, {
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
    exact_binding("research_breeding", 1.0, {
      "se-bioculture",
      "se-experimental-bioculture",
      "se-specimen-fish"
    }),
    exact_binding("research_bullets", 1.0, {
      "firearm-magazine",
      "shotgun-shell"
    }),
    exact_binding("research_bullets", 0.5, {
      "piercing-rounds-magazine",
      "piercing-shotgun-shell"
    }),
    exact_binding("research_bullets", 0.2, {
      "uranium-rounds-magazine"
    }),
    exact_binding("research_concrete", 1.0, {
      "se-recycle-radar",
      "stone-brick"
    }),
    exact_binding("research_concrete", 0.5, {
      "concrete",
      "hazard-concrete",
      "se-recycle-big-electric-pole"
    }),
    exact_binding("research_concrete", 0.2, {
      "refined-concrete",
      "refined-hazard-concrete"
    }),
    exact_binding("research_copper_cable", 1.0, {
      "copper-cable",
      "se-recycle-medium-electric-pole",
      "se-recycle-small-electric-pole",
      "se-recycle-small-iron-electric-pole"
    }),
    exact_binding("research_electric_energy", 1.0, {
      "accumulator",
      "se-space-capsule-scorched-scrapping",
      "se-space-capsule-scrapping",
      "solar-panel"
    }),
    exact_binding("research_electric_energy", 0.5, {
      "se-space-accumulator",
      "se-space-solar-panel"
    }),
    exact_binding("research_electric_energy", 0.2, {
      "se-space-accumulator-2",
      "se-space-solar-panel-2"
    }),
    exact_binding("research_electric_energy", 0.1, {
      "se-space-solar-panel-3"
    }),
    exact_binding("research_electric_engine", 1.0, {
      "electric-engine-unit"
    }),
    exact_binding("research_electronic_circuit", 1.0, {
      "electronic-circuit",
      "electronic-circuit-wood"
    }),
    exact_binding("research_engine", 1.0, {
      "engine-unit"
    }),
    exact_binding("research_grenades", 1.0, {
      "grenade"
    }),
    exact_binding("research_grenades", 0.5, {
      "cluster-grenade"
    }),
    exact_binding("research_heavy_ammo", 1.0, {
      "cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.5, {
      "explosive-cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.2, {
      "explosive-uranium-cannon-shell",
      "uranium-cannon-shell"
    }),
    exact_binding("research_heavy_ammo", 0.1, {
      "artillery-shell",
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
    exact_binding("research_inserters", 0.2, {
      "bulk-inserter"
    }),
    exact_binding("research_iron", 1.0, {
      "iron-plate",
      "se-iron-ingot-to-plate"
    }),
    exact_binding("research_iron_sticks", 1.0, {
      "iron-stick"
    }),
    exact_binding("research_landfill", 1.0, {
      "landfill",
      "landfill-copper-ore",
      "landfill-iron-ore",
      "landfill-sand",
      "landfill-se-beryllium-ore",
      "landfill-se-holmium-ore",
      "landfill-se-iridium-ore"
    }),
    exact_binding("research_low_density_structure", 1.0, {
      "low-density-structure",
      "se-low-density-structure-beryllium"
    }),
    exact_binding("research_rails", 1.0, {
      "rail"
    }),
    exact_binding("research_science_pack_productivity", 1.0, {
      "automation-science-pack",
      "chemical-science-pack",
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
    exact_binding("research_sulfuric_acid_productivity", 1.0, {
      "se-naquium-powder",
      "sulfuric-acid"
    }),
    exact_binding("research_walls", 1.0, {
      "stone-wall"
    }),
    exact_binding("research_walls", 0.5, {
      "gate"
    }),
  },
  replacement_product_target_families = {},
  excluded_product_target_recipes = {},
  -- AAI controls the two engine icons; keep those cross-profile facts separate.
}
