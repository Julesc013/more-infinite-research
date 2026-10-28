-- Exact selected published MIR 1.2.0 F200 native facts.
-- Generated once from the frozen 7714/C512 capture; static fixture data only.
return {
  technology_prefix = "recipe-prod-research_",
  technology_suffix = "-1",
  direct = "recipe-prod-research_gears-1",
  robot_battery = "recipe-prod-research_robot_battery-1",
  rows = {
    ["recipe-prod-research_advanced_circuit-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "advanced-circuit",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_batteries-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "battery",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_belts-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "transport-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "splitter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "underground-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "fast-underground-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "fast-splitter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "fast-transport-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "express-transport-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "express-underground-belt",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "express-splitter",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_bullets-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "firearm-magazine",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "shotgun-shell",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "piercing-rounds-magazine",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "piercing-shotgun-shell",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "uranium-rounds-magazine",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_concrete-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "stone-brick",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "concrete",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "hazard-concrete",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "refined-concrete",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "refined-hazard-concrete",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_copper-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "copper-plate",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_copper_cable-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "copper-cable",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_electric_energy-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "solar-panel",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "accumulator",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_electric_engine-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "electric-engine-unit",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_electric_shooting_speed-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "60 * 1.5^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          ammo_category = "electric",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["recipe-prod-research_electronic_circuit-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "electronic-circuit",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_engine-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "engine-unit",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_explosives-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "explosives",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_flamethrower_shooting_speed-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "60 * 1.5^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          ammo_category = "flamethrower",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["recipe-prod-research_flying_robot_frame-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "flying-robot-frame",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_furnace-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.20000000000000001,
          recipe = "stone-furnace",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "steel-furnace",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "electric-furnace",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_gears-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "iron-gear-wheel",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_grenades-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "grenade",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "cluster-grenade",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_inserters-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "inserter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "burner-inserter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "fast-inserter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "long-handed-inserter",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "bulk-inserter",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_iron-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "iron-plate",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_iron_sticks-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "iron-stick",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_low_density_structure-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "low-density-structure",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_mining_drill-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.20000000000000001,
          recipe = "burner-mining-drill",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "electric-mining-drill",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_modules-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "speed-module",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "productivity-module",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "efficiency-module",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "speed-module-2",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "productivity-module-2",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "efficiency-module-2",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "speed-module-3",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "productivity-module-3",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "efficiency-module-3",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_plastic-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "plastic-bar",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_processing_unit-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "processing-unit",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_rails-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "rail",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_robot_battery-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 1.2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          modifier = 0.10000000000000001,
          type = "worker-robot-battery"
        }
      }
    },
    ["recipe-prod-research_rocket_fuel-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "rocket-fuel",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_rocket_shooting_speed-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "60 * 1.5^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          ammo_category = "rocket",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        },
        {
          ammo_category = "cannon-shell",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["recipe-prod-research_rockets-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "rocket",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "explosive-rocket",
          type = "change-recipe-productivity"
        },
        {
          change = 0.02,
          recipe = "atomic-bomb",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_science_pack_productivity-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          },
          {
            "utility-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "utility-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "automation-science-pack",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "logistic-science-pack",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "chemical-science-pack",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "military-science-pack",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "production-science-pack",
          type = "change-recipe-productivity"
        },
        {
          change = 0.10000000000000001,
          recipe = "utility-science-pack",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_sulfur-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "sulfur",
          type = "change-recipe-productivity"
        }
      }
    },
    ["recipe-prod-research_walls-1"] = {
      level = 1,
      max_level = "infinite",
      upgrade = true,
      enabled_present = false,
      enabled = nil,
      unit = {
        count_formula = "8000 * 2^(L-1)",
        time = 60,
        ingredients = {
          {
            "automation-science-pack",
            1
          },
          {
            "logistic-science-pack",
            1
          },
          {
            "chemical-science-pack",
            1
          },
          {
            "production-science-pack",
            1
          },
          {
            "military-science-pack",
            1
          },
          {
            "space-science-pack",
            1
          }
        }
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      },
      effects = {
        {
          change = 0.10000000000000001,
          recipe = "stone-wall",
          type = "change-recipe-productivity"
        },
        {
          change = 0.050000000000000003,
          recipe = "gate",
          type = "change-recipe-productivity"
        }
      }
    }
  },
  settings = {
    ["ips-enable-research_advanced_circuit"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_batteries"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_belts"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_bioflux"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_breeding"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_bullets"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_carbon_fiber"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_concrete"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_copper"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_copper_cable"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_electric_energy"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_electric_engine"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_electric_shooting_speed"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_electronic_circuit"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_engine"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_explosives"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_flamethrower_shooting_speed"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_flying_robot_frame"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_furnace"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_gears"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_grenades"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_holmium"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_inserters"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_inventory_capacity"] = {
      kind = "bool-setting",
      default_value = false
    },
    ["ips-enable-research_iron"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_iron_sticks"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_lithium"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_low_density_structure"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_mining_drill"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_modules"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_plastic"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_processing_unit"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_quantum_processor"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_rails"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_robot_battery"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_rocket_fuel"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_rocket_shooting_speed"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_rockets"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_science_pack_productivity"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_sulfur"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_supercapacitor"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_superconductor"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_tungsten"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-enable-research_walls"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-require-space-gate"] = {
      kind = "bool-setting",
      default_value = true
    },
    ["ips-cost-growth-research_advanced_circuit"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_batteries"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_belts"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_bioflux"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_breeding"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_bullets"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_carbon_fiber"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_concrete"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_copper"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_copper_cable"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_electric_energy"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_electric_engine"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_electric_shooting_speed"] = {
      kind = "double-setting",
      default_value = 1.5
    },
    ["ips-cost-growth-research_electronic_circuit"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_engine"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_explosives"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_flamethrower_shooting_speed"] = {
      kind = "double-setting",
      default_value = 1.5
    },
    ["ips-cost-growth-research_flying_robot_frame"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_furnace"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_gears"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_grenades"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_holmium"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_inserters"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_inventory_capacity"] = {
      kind = "double-setting",
      default_value = 1.1000000000000001
    },
    ["ips-cost-growth-research_iron"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_iron_sticks"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_lithium"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_low_density_structure"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_mining_drill"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_modules"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_plastic"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_processing_unit"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_quantum_processor"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_rails"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_robot_battery"] = {
      kind = "double-setting",
      default_value = 1.2
    },
    ["ips-cost-growth-research_rocket_fuel"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_rocket_shooting_speed"] = {
      kind = "double-setting",
      default_value = 1.5
    },
    ["ips-cost-growth-research_rockets"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_science_pack_productivity"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_sulfur"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_supercapacitor"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_superconductor"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_tungsten"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-growth-research_walls"] = {
      kind = "double-setting",
      default_value = 2
    },
    ["ips-cost-base-research_advanced_circuit"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_batteries"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_belts"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_bioflux"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_breeding"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_bullets"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_carbon_fiber"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_concrete"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_copper"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_copper_cable"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_electric_energy"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_electric_engine"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_electric_shooting_speed"] = {
      kind = "int-setting",
      default_value = 60
    },
    ["ips-cost-base-research_electronic_circuit"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_engine"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_explosives"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_flamethrower_shooting_speed"] = {
      kind = "int-setting",
      default_value = 60
    },
    ["ips-cost-base-research_flying_robot_frame"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_furnace"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_gears"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_grenades"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_holmium"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_inserters"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_inventory_capacity"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_iron"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_iron_sticks"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_lithium"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_low_density_structure"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_mining_drill"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_modules"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_plastic"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_processing_unit"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_quantum_processor"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_rails"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_robot_battery"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_rocket_fuel"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_rocket_shooting_speed"] = {
      kind = "int-setting",
      default_value = 60
    },
    ["ips-cost-base-research_rockets"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_science_pack_productivity"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_sulfur"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_supercapacitor"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_superconductor"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_tungsten"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-cost-base-research_walls"] = {
      kind = "int-setting",
      default_value = 8000
    },
    ["ips-max-level-research_advanced_circuit"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_batteries"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_belts"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_bioflux"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_breeding"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_bullets"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_carbon_fiber"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_concrete"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_copper"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_copper_cable"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_electric_energy"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_electric_engine"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_electric_shooting_speed"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_electronic_circuit"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_engine"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_explosives"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_flamethrower_shooting_speed"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_flying_robot_frame"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_furnace"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_gears"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_grenades"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_holmium"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_inserters"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_inventory_capacity"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_iron"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_iron_sticks"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_lithium"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_low_density_structure"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_mining_drill"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_modules"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_plastic"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_processing_unit"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_quantum_processor"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_rails"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_robot_battery"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_rocket_fuel"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_rocket_shooting_speed"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_rockets"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_science_pack_productivity"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_sulfur"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_supercapacitor"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_superconductor"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_tungsten"] = {
      kind = "int-setting",
      default_value = 0
    },
    ["ips-max-level-research_walls"] = {
      kind = "int-setting",
      default_value = 0
    }
  },
  setting_counts = {
    ["bool-setting"] = 45,
    ["double-setting"] = 44,
    ["int-setting"] = 88
  },
  weapons = {
    ["weapon-shooting-speed-1"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.10000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-2"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.20000000000000001,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.20000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-3"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.20000000000000001,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.20000000000000001,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-4"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.29999999999999999,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.29999999999999999,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-5"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.29999999999999999,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.40000000000000002,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-6"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.40000000000000002,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.40000000000000002,
          type = "gun-speed"
        }
      }
    },
    ["weapon-shooting-speed-7"] = {
      effects = {
        {
          ammo_category = "bullet",
          modifier = 0.40000000000000002,
          type = "gun-speed"
        },
        {
          ammo_category = "shotgun-shell",
          modifier = 0.40000000000000002,
          type = "gun-speed"
        }
      }
    }
  },
  finite_weapon_seed = "weapon-shooting-speed-1",
  gun_categories = {
    "rocket",
    "cannon-shell",
    "electric",
    "flamethrower"
  },
  direct_gun_speed = {
    rocket = 0.10000000000000001,
    ["cannon-shell"] = 0.10000000000000001,
    electric = 0.10000000000000001,
    flamethrower = 0.10000000000000001
  },
  finite_owner_gun_speed = {
    bullet = 0.10000000000000001,
    ["shotgun-shell"] = 0.10000000000000001
  },
  source_formula = "8000 * 2^(L-1)",
  source_time = 60
}
