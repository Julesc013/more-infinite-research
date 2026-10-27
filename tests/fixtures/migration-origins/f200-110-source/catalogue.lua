-- Exact published MIR 1.1.0 facts for Base 2.0.77.  These are source-era
-- inputs for a disposable origin save, not a MIR5 catalogue or a recipe scan.
local function recipe(recipe, change)
  return {type = "change-recipe-productivity", recipe = recipe, change = change}
end

return {
  technology_prefix = "recipe-prod-research_",
  technology_suffix = "-1",
  direct = "recipe-prod-research_gears-1",
  robot_battery = "recipe-prod-research_robot_battery-1",
  source_formula = "8000 * 2^(L-1)",
  source_time = 60,
  settings = {
    ["ips-require-space-gate"] = true,
    ["ips-enable-research_breeding"] = true,
    ["ips-enable-research_plastic"] = true,
    ["ips-enable-research_sulfur"] = true,
    ["ips-enable-research_batteries"] = true,
    ["ips-enable-research_explosives"] = true,
    ["ips-enable-research_gears"] = true,
    ["ips-enable-research_iron_sticks"] = true,
    ["ips-enable-research_copper_cable"] = true,
    ["ips-enable-research_electronic_circuit"] = true,
    ["ips-enable-research_advanced_circuit"] = true,
    ["ips-enable-research_processing_unit"] = true,
    ["ips-enable-research_low_density_structure"] = true,
    ["ips-enable-research_rocket_fuel"] = true,
    ["ips-enable-research_copper"] = true,
    ["ips-enable-research_iron"] = true,
    ["ips-enable-research_engine"] = true,
    ["ips-enable-research_electric_engine"] = true,
    ["ips-enable-research_flying_robot_frame"] = true,
    ["ips-enable-research_tungsten"] = true,
    ["ips-enable-research_holmium"] = true,
    ["ips-enable-research_supercapacitor"] = true,
    ["ips-enable-research_superconductor"] = true,
    ["ips-enable-research_bioflux"] = true,
    ["ips-enable-research_carbon_fiber"] = true,
    ["ips-enable-research_lithium"] = true,
    ["ips-enable-research_quantum_processor"] = true,
    ["ips-enable-research_modules"] = true,
    ["ips-enable-research_belts"] = true,
    ["ips-enable-research_inserters"] = true,
    ["ips-enable-research_bullets"] = true,
    ["ips-enable-research_rockets"] = true,
    ["ips-enable-research_inventory_capacity"] = false,
    ["ips-enable-research_robot_battery"] = true,
    ["ips-enable-research_science_pack_productivity"] = true,
    ["ips-enable-research_walls"] = true,
    ["ips-enable-research_grenades"] = true,
    ["ips-enable-research_rails"] = true,
    ["ips-enable-research_electric_energy"] = true,
    ["ips-enable-research_concrete"] = true,
    ["ips-enable-research_furnace"] = true,
    ["ips-enable-research_mining_drill"] = true,
  },
  -- Exact original `U.pick_science_for_stream` and
  -- `U.build_prereqs_for` outputs on Base 2.0.77.  The enabled space gate
  -- appends only a prerequisite; it never changes the unit ingredients.
  science = {
    ordinary = {
      ingredients = {
        ["automation-science-pack"] = 1, ["logistic-science-pack"] = 1,
        ["chemical-science-pack"] = 1, ["production-science-pack"] = 1,
      },
      prerequisites = {
        ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
        ["chemical-science-pack"] = true, ["production-science-pack"] = true,
        ["space-science-pack"] = true,
      },
    },
    space = {
      ingredients = {
        ["automation-science-pack"] = 1, ["logistic-science-pack"] = 1,
        ["chemical-science-pack"] = 1, ["production-science-pack"] = 1,
        ["space-science-pack"] = 1,
      },
      prerequisites = {
        ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
        ["chemical-science-pack"] = true, ["production-science-pack"] = true,
        ["space-science-pack"] = true,
      },
    },
    military_space = {
      ingredients = {
        ["automation-science-pack"] = 1, ["logistic-science-pack"] = 1,
        ["chemical-science-pack"] = 1, ["production-science-pack"] = 1,
        ["military-science-pack"] = 1, ["space-science-pack"] = 1,
      },
      prerequisites = {
        ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
        ["chemical-science-pack"] = true, ["production-science-pack"] = true,
        ["military-science-pack"] = true, ["space-science-pack"] = true,
      },
    },
    military_gate = {
      ingredients = {
        ["automation-science-pack"] = 1, ["logistic-science-pack"] = 1,
        ["chemical-science-pack"] = 1, ["production-science-pack"] = 1,
        ["military-science-pack"] = 1,
      },
      prerequisites = {
        ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
        ["chemical-science-pack"] = true, ["production-science-pack"] = true,
        ["military-science-pack"] = true, ["space-science-pack"] = true,
      },
    },
    all_f200_tools = {
      ingredients = {
        ["automation-science-pack"] = 1, ["logistic-science-pack"] = 1,
        ["chemical-science-pack"] = 1, ["production-science-pack"] = 1,
        ["military-science-pack"] = 1, ["utility-science-pack"] = 1,
        ["space-science-pack"] = 1,
      },
      prerequisites = {
        ["automation-science-pack"] = true, ["logistic-science-pack"] = true,
        ["chemical-science-pack"] = true, ["production-science-pack"] = true,
        ["military-science-pack"] = true, ["utility-science-pack"] = true,
        ["space-science-pack"] = true,
      },
    },
  },
  -- `rows` is literal archived 1.1.0 config plus F200 Base recipe-output
  -- admission.  Effects are compared as multisets because tech-gen.lua
  -- enumerates `pairs(data.raw.recipe)` and does not author an output order.
  rows = {
    ["recipe-prod-research_plastic-1"] = {science = "ordinary", effects = {recipe("plastic-bar", .10)}},
    ["recipe-prod-research_sulfur-1"] = {science = "ordinary", effects = {recipe("sulfur", .10)}},
    ["recipe-prod-research_batteries-1"] = {science = "ordinary", effects = {recipe("battery", .10)}},
    ["recipe-prod-research_explosives-1"] = {science = "ordinary", effects = {recipe("explosives", .10)}},
    ["recipe-prod-research_gears-1"] = {science = "ordinary", effects = {recipe("iron-gear-wheel", .10)}},
    ["recipe-prod-research_iron_sticks-1"] = {science = "ordinary", effects = {recipe("iron-stick", .10)}},
    ["recipe-prod-research_copper_cable-1"] = {science = "ordinary", effects = {recipe("copper-cable", .10)}},
    ["recipe-prod-research_electronic_circuit-1"] = {science = "ordinary", effects = {recipe("electronic-circuit", .10)}},
    ["recipe-prod-research_advanced_circuit-1"] = {science = "ordinary", effects = {recipe("advanced-circuit", .10)}},
    ["recipe-prod-research_processing_unit-1"] = {science = "ordinary", effects = {recipe("processing-unit", .10)}},
    ["recipe-prod-research_low_density_structure-1"] = {science = "ordinary", effects = {recipe("low-density-structure", .10)}},
    ["recipe-prod-research_rocket_fuel-1"] = {science = "ordinary", effects = {recipe("rocket-fuel", .10)}},
    ["recipe-prod-research_copper-1"] = {science = "ordinary", effects = {recipe("copper-plate", .10)}},
    ["recipe-prod-research_iron-1"] = {science = "ordinary", effects = {recipe("iron-plate", .10)}},
    ["recipe-prod-research_engine-1"] = {science = "ordinary", effects = {recipe("engine-unit", .10)}},
    ["recipe-prod-research_electric_engine-1"] = {science = "ordinary", effects = {recipe("electric-engine-unit", .10)}},
    ["recipe-prod-research_flying_robot_frame-1"] = {science = "ordinary", effects = {recipe("flying-robot-frame", .10)}},
    ["recipe-prod-research_modules-1"] = {science = "ordinary", effects = {
      recipe("productivity-module", .10), recipe("speed-module", .10), recipe("efficiency-module", .10),
      recipe("productivity-module-2", .05), recipe("speed-module-2", .05), recipe("efficiency-module-2", .05),
      recipe("productivity-module-3", .02), recipe("speed-module-3", .02), recipe("efficiency-module-3", .02),
      recipe("productivity-module", .01), recipe("speed-module", .01), recipe("efficiency-module", .01),
    }},
    ["recipe-prod-research_belts-1"] = {science = "space", effects = {
      recipe("transport-belt", .10), recipe("underground-belt", .10), recipe("splitter", .10),
      recipe("fast-transport-belt", .05), recipe("fast-underground-belt", .05), recipe("fast-splitter", .05),
      recipe("express-transport-belt", .02), recipe("express-underground-belt", .02), recipe("express-splitter", .02),
    }},
    ["recipe-prod-research_inserters-1"] = {science = "space", effects = {
      recipe("inserter", .10), recipe("burner-inserter", .10), recipe("fast-inserter", .05),
      recipe("long-handed-inserter", .05), recipe("bulk-inserter", .02),
    }},
    ["recipe-prod-research_bullets-1"] = {science = "military_space", effects = {
      recipe("firearm-magazine", .10), recipe("shotgun-shell", .10),
      recipe("piercing-rounds-magazine", .05), recipe("piercing-shotgun-shell", .05),
      recipe("uranium-rounds-magazine", .02),
    }},
    ["recipe-prod-research_rockets-1"] = {science = "military_gate", effects = {
      recipe("rocket", .10), recipe("explosive-rocket", .05), recipe("atomic-bomb", .02),
    }},
    ["recipe-prod-research_robot_battery-1"] = {science = "space", effects = {
      {type = "worker-robot-battery", modifier = .10},
    }},
    ["recipe-prod-research_science_pack_productivity-1"] = {science = "all_f200_tools", effects = {
      recipe("automation-science-pack", .10), recipe("logistic-science-pack", .10), recipe("chemical-science-pack", .10),
      recipe("military-science-pack", .10), recipe("production-science-pack", .10), recipe("utility-science-pack", .10),
    }},
    ["recipe-prod-research_walls-1"] = {science = "military_space", effects = {recipe("stone-wall", .10), recipe("gate", .05)}},
    ["recipe-prod-research_grenades-1"] = {science = "military_space", effects = {recipe("grenade", .10), recipe("cluster-grenade", .05)}},
    ["recipe-prod-research_rails-1"] = {science = "space", effects = {recipe("rail", .10)}},
    ["recipe-prod-research_electric_energy-1"] = {science = "ordinary", effects = {recipe("solar-panel", .10), recipe("accumulator", .10)}},
    ["recipe-prod-research_concrete-1"] = {science = "space", effects = {
      recipe("stone-brick", .10), recipe("concrete", .05), recipe("hazard-concrete", .05),
      recipe("refined-concrete", .02), recipe("refined-hazard-concrete", .02),
    }},
    ["recipe-prod-research_furnace-1"] = {science = "ordinary", effects = {
      recipe("stone-furnace", .20), recipe("steel-furnace", .10), recipe("electric-furnace", .05),
    }},
    ["recipe-prod-research_mining_drill-1"] = {science = "ordinary", effects = {
      recipe("burner-mining-drill", .20), recipe("electric-mining-drill", .10),
    }},
  },
}
