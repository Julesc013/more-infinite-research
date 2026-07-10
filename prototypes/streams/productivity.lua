local overlay_loader = require("prototypes.mir.compatibility.overlay_loader")

local air_scrubbing_overlay = overlay_loader.get("air-scrubbing")
local air_scrubbing_capability = air_scrubbing_overlay.capabilities["recipe-productivity"]
local atan_ash_overlay = overlay_loader.get("atan-ash")
local atan_ash_capability = atan_ash_overlay.capabilities["recipe-productivity"]

local function lua_pattern_escape(value)
  return (tostring(value or ""):gsub("([^%w])", "%%%1"))
end

local function exact_recipe_patterns(recipes)
  local out = {}
  for _, recipe_name in ipairs(recipes or {}) do
    table.insert(out, "^" .. lua_pattern_escape(recipe_name) .. "$")
  end
  return out
end

return {
  research_copper = { items={"copper-plate"}, icon_item="copper-plate" },
  research_iron   = { items={"iron-plate"}, icon_item="iron-plate" },
  research_gears = { items={"iron-gear-wheel"}, icon_item="iron-gear-wheel", exclude_ingredient_patterns={"scrap"} },
  research_iron_sticks = { items={"iron-stick"}, icon_item="iron-stick", exclude_ingredient_patterns={"scrap"} },
  research_copper_cable = { items={"copper-cable"}, icon_item="copper-cable", exclude_ingredient_patterns={"scrap"} },

  research_electronic_circuit = { items={"electronic-circuit"}, icon_tech="electronics", exclude_ingredient_patterns={"scrap"} },
  research_advanced_circuit = { items={"advanced-circuit"}, icon_tech="advanced-circuit", exclude_ingredient_patterns={"scrap"} },
  research_processing_unit = {
    items={"processing-unit"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/processing-unit-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="processing-unit"},
      {technology="advanced-electronics-2"}
    },
    adopt_into_existing_productivity_tech = {
      tech = "processing-unit-productivity",
      products = {"processing-unit"},
      require_infinite = true,
      require_existing_recipe_productivity_effects = true,
      change_policy = "copy-owner"
    }
  },

  research_plastic = {
    items={"plastic-bar"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/plastics-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="plastics"}
    },
    adopt_into_existing_productivity_tech = {
      tech = "plastic-bar-productivity",
      products = {"plastic-bar"},
      require_infinite = true,
      require_existing_recipe_productivity_effects = true,
      change_policy = "copy-owner"
    }
  },
  research_sulfur  = { items={"sulfur"}, icon_tech="sulfur-processing", exclude_ingredient_patterns={"asteroid"} },
  research_batteries = { items={"battery"}, icon_tech="battery", exclude_ingredient_patterns={"scrap"} },
  research_explosives = { items={"explosives"}, item_patterns={"^bio%-explosives$"}, icon_tech="explosives" },

  research_engine = { items={"engine-unit"}, icon_tech="engine" },
  research_electric_engine = { items={"electric-engine-unit"}, icon_tech="electric-engine" },
  research_flying_robot_frame = { items={"flying-robot-frame"}, icon_tech="robotics" },

  research_low_density_structure = {
    items={"low-density-structure"},
    icon_candidates={
      {
        icon="__space-age__/graphics/technology/low-density-structure-productivity.png",
        icon_size=256,
        inactive_mod_asset="space-age"
      },
      {technology="low-density-structure"}
    },
    adopt_into_existing_productivity_tech = {
      tech = "low-density-structure-productivity",
      products = {"low-density-structure"},
      require_infinite = true,
      require_existing_recipe_productivity_effects = true,
      change_policy = "copy-owner"
    }
  },
  research_rocket_fuel = {
    items={"rocket-fuel"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/rocket-fuel-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="rocket-fuel"}
    },
    adopt_into_existing_productivity_tech = {
      tech = "rocket-fuel-productivity",
      products = {"rocket-fuel"},
      require_infinite = true,
      require_existing_recipe_productivity_effects = true,
      change_policy = "copy-owner"
    }
  },

  research_thruster_fuel_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_thruster_fuel_productivity"},
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_fluid = {"thruster-fuel"}
    },
    required_fluids = {"thruster-fuel"},
    fluids = {"thruster-fuel"},
    exclude_recipe_patterns = {"^empty%-.*%-barrel$"},
    icon_candidates = {
      {fluid = "thruster-fuel"},
      {technology = "space-platform-thruster", required_mod = "space-age"},
      {icon = "__space-age__/graphics/icons/fluid/thruster-fuel.png", icon_size = 64, inactive_mod_asset = "space-age"}
    }
  },

  research_thruster_oxidizer_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_thruster_oxidizer_productivity"},
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_fluid = {"thruster-oxidizer"}
    },
    required_fluids = {"thruster-oxidizer"},
    fluids = {"thruster-oxidizer"},
    exclude_recipe_patterns = {"^empty%-.*%-barrel$"},
    icon_candidates = {
      {fluid = "thruster-oxidizer"},
      {technology = "space-platform-thruster", required_mod = "space-age"},
      {icon = "__space-age__/graphics/icons/fluid/thruster-oxidizer.png", icon_size = 64, inactive_mod_asset = "space-age"}
    }
  },

  research_oil_processing_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_oil_processing_productivity"},
    recipe_patterns = {
      "^basic%-oil%-processing$",
      "^advanced%-oil%-processing$",
      "^coal%-liquefaction$",
      "^simple%-coal%-liquefaction$"
    },
    icon_candidates = {
      {technology = "advanced-oil-processing"},
      {technology = "oil-processing"},
      {icon = "__base__/graphics/icons/fluid/advanced-oil-processing.png", icon_size = 64}
    }
  },

  research_oil_cracking_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_oil_cracking_productivity"},
    recipe_patterns = {
      "^heavy%-oil%-cracking$",
      "^light%-oil%-cracking$"
    },
    icon_candidates = {
      {technology = "oil-processing"},
      {technology = "advanced-oil-processing"},
      {icon = "__base__/graphics/icons/fluid/heavy-oil-cracking.png", icon_size = 64}
    }
  },

  research_lubricant_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_lubricant_productivity"},
    required_fluids = {"lubricant"},
    fluids = {"lubricant"},
    exclude_recipe_patterns = {"^empty%-.*%-barrel$"},
    icon_candidates = {
      {technology = "lubricant"},
      {fluid = "lubricant"}
    }
  },

  research_sulfuric_acid_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_sulfuric_acid_productivity"},
    required_fluids = {"sulfuric-acid"},
    fluids = {"sulfuric-acid"},
    recipe_patterns = {
      "^acid%-neutralisation$",
      "^acid%-neutralization$"
    },
    exclude_recipe_patterns = {"^empty%-.*%-barrel$"},
    icon_candidates = {
      {fluid = "sulfuric-acid"},
      {technology = "sulfur-processing"}
    }
  },

  research_air_scrubbing_clean_filter = {
    localised_name = {"", "Air Scrubbing clean-filter productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    ui_visibility = {
      mode = "visible-if-mods-any",
      mods_any = air_scrubbing_overlay.applies_when.mods,
      hidden_reason = "requires-atan-air-scrubbing"
    },
    generation_requirements = {
      require_any_recipe = air_scrubbing_capability.exact_recipes,
      deny_risk_flags = air_scrubbing_capability.deny_risk_flags
    },
    science_packs = "derive-from-unlocks",
    prerequisites = "derive-from-unlocks",
    settings_note = {
      "",
      "Targets only exact clean filter crafting recipes. Scrubbing, cleaning, recovery, " ..
        "recycling, and environmental-removal recipes stay diagnostic-only."
    },
    manifest_id = air_scrubbing_capability.stream.id,
    groups = {
      {
        change = 0.05,
        recipe_patterns = exact_recipe_patterns(air_scrubbing_capability.exact_recipes)
      }
    },
    icon_candidates = {
      {item = "atan-pollution-filter"},
      {item = "atan-spore-filter"},
      {technology = "atan-pollution-scrubbing"},
      {technology = "atan-spore-scrubbing"},
      {item = "coal"}
    }
  },

  research_ash_separation = {
    localised_name = {"", "Ash separation productivity"},
    localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
    ui_visibility = {
      mode = "visible-if-mods-any",
      mods_any = atan_ash_overlay.applies_when.mods,
      hidden_reason = "requires-atan-ash"
    },
    generation_requirements = {
      require_any_recipe = atan_ash_capability.exact_recipes,
      deny_risk_flags = atan_ash_capability.deny_risk_flags
    },
    science_packs = "derive-from-unlocks",
    prerequisites = "derive-from-unlocks",
    settings_note = {
      "",
      "Targets only the exact ATAN Ash separation recipe. Landfill, brick, nutrient, " ..
        "foundation, tile, and recovery-style ash sinks stay outside this stream."
    },
    manifest_id = atan_ash_capability.stream.id,
    groups = {
      {
        change = 0.05,
        recipe_patterns = exact_recipe_patterns(atan_ash_capability.exact_recipes)
      }
    },
    icon_candidates = {
      {item = "atan-ash"},
      {technology = "atan-ash-processing"},
      {item = "coal"}
    }
  },

  research_tungsten = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"tungsten-plate", "tungsten-carbide"}
    },
    items={"tungsten-plate","tungsten-carbide"},
    icon_item="tungsten-plate",
    icon_tech="tungsten-processing"
  },
  research_lithium = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"lithium-plate", "lithium"}
    },
    icon_tech="lithium-processing",
    groups = {
    { change = 0.10, items = { "lithium-plate" } },
    { change = 0.05, items = { "lithium" }, recipe_patterns = { "^lithium$" } }
  } },
  research_holmium = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"holmium-plate"}
    },
    items={"holmium-plate"},
    icon_tech="holmium-processing"
  },
  research_supercapacitor = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"supercapacitor"}
    },
    items={"supercapacitor"},
    icon_tech="supercapacitor"
  },
  research_superconductor = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"superconductor"}
    },
    items={"superconductor"},
    icon_tech="superconductor"
  },
  research_quantum_processor = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"quantum-processor"}
    },
    items={"quantum-processor"},
    icon_tech="quantum-processor"
  },
  research_carbon = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"carbon"}
    },
    icon_item="carbon",
    groups = {
    { change = 0.10, items = { "carbon" }, recipe_patterns = {
      "^carbonic%-asteroid%-crushing$",
      "^advanced%-carbonic%-asteroid%-crushing$",
      "^carbon$"
    }, exclude_recipe_patterns = { "^burnt%-spoilage$" } },
    { change = 0.05, recipe_patterns = { "^burnt%-spoilage$" } },
    { change = 0.02, recipe_patterns = { "^coal%-synthesis$" } }
  } },
  research_carbon_fiber = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"carbon-fiber"}
    },
    items={"carbon-fiber"},
    icon_tech="carbon-fiber"
  },
  research_ice = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"ice"}
    },
    items={"ice"},
    icon_item="ice",
    recipe_patterns = {
    "^oxide%-asteroid%-crushing$",
    "^advanced%-oxide%-asteroid%-crushing$"
  } },

  research_bioflux = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"bioflux"}
    },
    items={"bioflux"},
    icon_tech="bioflux"
  },
  research_bacteria_cultivation = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_recipe = {"iron-bacteria-cultivation", "copper-bacteria-cultivation"}
    },
    icon_tech = "bacteria-cultivation",
    recipe_patterns = {
    "^iron%-bacteria%-cultivation$",
    "^copper%-bacteria%-cultivation$"
  } },
  research_breeding = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"raw-fish", "biter-egg", "pentapod-egg"}
    },
    items = {"raw-fish","biter-egg","pentapod-egg"},
    mode = "by_category_or_match",
    match = { name_patterns={"cultivation","culture","breeding"} },
    exclude_recipe_patterns = {
      "^iron%-bacteria%-cultivation$",
      "^copper%-bacteria%-cultivation$",
      "%-incineration$",
      "%-incinerate$"
    },
    icon_tech = "fish-breeding"
  },

  research_grenades = { icon_item="grenade", groups = {
    {change=0.10, items={"grenade"}},
    {change=0.05, items={"cluster-grenade"}}
  } },

  research_walls = { icon_tech="gate", icon_item="stone-wall", groups = {
    {change=0.10, items={"stone-wall"}},
    {change=0.05, items={"gate"}}
  } },

  research_landfill = { icon_tech = "landfill", groups = {
    { change = 0.10, items = { "landfill" } },
    { change = 0.05, items = { "foundation" } }
  }, exclude_recipe_patterns = {
    "^atan%-landfill%-from%-ash$",
    "^atan%-foundation%-from%-ash$"
  }, exclude_ingredient_patterns={"scrap"} },

  research_artificial_soil = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item_family = {"artificial-soil", "overgrowth-soil"}
    },
    icon_tech = "artificial-soil",
    groups = {
    { change = 0.10, item_patterns = { "^artificial%-.+%-soil$" } },
    { change = 0.05, item_patterns = { "^overgrowth%-.+%-soil$" } }
  } },

  research_molten_metals = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_recipe = {"molten-iron-from-lava", "molten-copper-from-lava", "iron-ore-melting", "copper-ore-melting"}
    },
    icon_tech = "foundry",
    groups = {
    { change = 0.10, recipe_patterns = { "^molten%-iron%-from%-lava$", "^molten%-copper%-from%-lava$" } },
    { change = 0.05, recipe_patterns = { "^iron%-ore%-melting$", "^copper%-ore%-melting$" } }
  }, exclude_ingredient_patterns={"scrap"} },

  research_rails = { icon_item = "rail", icon_candidates = {
    { technology = "elevated-rail", required_mod = "elevated-rails" },
    { icon = "__elevated-rails__/graphics/technology/elevated-rail.png", icon_size = 256, inactive_mod_asset = "elevated-rails" }
  }, groups = {
    { change = 0.10, items = { "rail" } },
    { change = 0.05, items = { "rail-support" } },
    { change = 0.02, items = { "rail-ramp" } }
  } },

  research_concrete = { icon_tech = "concrete", groups = {
    { change = 0.10, items = { "stone-brick" } },
    { change = 0.05, items = { "concrete", "hazard-concrete" } },
    { change = 0.02, items = { "refined-concrete", "refined-hazard-concrete" } }
  }, exclude_recipe_patterns = {
    "^atan%-stone%-brick%-from%-ash$"
  }, exclude_ingredient_patterns={"scrap"} },

  research_furnace = { icon_tech = "advanced-material-processing-2", groups = {
    { change = 0.20, items = { "stone-furnace" } },
    { change = 0.10, items = { "steel-furnace" } },
    { change = 0.05, items = { "electric-furnace" } },
    { change = 0.02, items = { "foundry" }, item_patterns = { "^foundry$" } }
  } },

  research_mining_drill = { icon_tech = "electric-mining", icon_item = "electric-mining-drill", groups = {
    { change = 0.20, items = { "burner-mining-drill" } },
    { change = 0.10, items = { "electric-mining-drill" } },
    { change = 0.05, items = { "big-mining-drill" }, item_patterns = {
      "^big%-mining%-drill$",
      "^omega%-drill$",
      "^omega%-tau$",
      "^.+%-mining%-drill$",
      "^.+%-drill$"
    } }
  } },

  research_electric_energy = { icon_tech="electric-energy-accumulators", groups = {
    { change=0.10, items={"solar-panel","accumulator"} },
    { change=0.05, items={"advanced-solar","advanced-accumulator"} },
    { change=0.02, items={"elite-solar","elite-accumulator"} },
    { change=0.01, items={"ultimate-solar","ultimate-accumulator"} }
  } },

  research_bullets = { icon_tech="military", groups = {
    { change=0.10, items={"firearm-magazine","shotgun-shell"} },
    { change=0.05, items={"piercing-rounds-magazine","piercing-shotgun-shell"} },
    { change=0.02, items={"uranium-rounds-magazine","uranium-shotgun-shell"} },
    { change=0.01, item_patterns={
      "^plutonium%-.+magazine$","^plutonium%-.+shotgun%-shell$",
      "^tungsten%-.+magazine$","^tungsten%-.+shotgun%-shell$"
    } }
  }},

  research_heavy_ammo = { icon_item="cannon-shell", groups = {
    { change=0.10, items={"cannon-shell"} },
    { change=0.05, items={"explosive-cannon-shell"} },
    { change=0.02, items={"uranium-cannon-shell","explosive-uranium-cannon-shell"} },
    { change=0.01, items={"artillery-shell","railgun-ammo"}, item_patterns={
      "^.+%-cannon%-shell$","^.+%-artillery%-shell$","^.+%-railgun%-ammo$"
    } }
  }},

  research_rockets = { icon_tech="rocketry", groups = {
    { change=0.10, items={"rocket"} },
    { change=0.05, items={"explosive-rocket"} },
    { change=0.02, items={"atomic-bomb"} },
    { change=0.01, items={"plutonium-bomb"}, item_patterns={"^plutonium%-bomb$","^plutonium%-.+bomb$"} }
  }},

  research_armor_components = { icon_tech="power-armor", groups = {
    { change=0.05, item_patterns={
      "^.+%-armor%-plating$","^.+%-armour%-plating$",
      "^armor%-plating.*$","^armour%-plating.*$"
    } },
    { change=0.02, item_patterns={
      "^.+%-armor%-plate$","^.+%-armour%-plate$",
      "^armor%-plate.*$","^armour%-plate.*$"
    } }
  }},

  research_modules = { icon_tech="modules", groups = {
    { change=0.10, items={"productivity-module","speed-module","efficiency-module","quality-module"} },
    { change=0.05, items={"productivity-module-2","speed-module-2","efficiency-module-2","quality-module-2"} },
    { change=0.02, items={"productivity-module-3","speed-module-3","efficiency-module-3","quality-module-3"} }
  }},

  research_belts = { icon_tech="logistics", groups = {
    {
      change=0.10,
      items={"transport-belt","underground-belt","splitter","loader","aai-loader","basic-loader"},
      item_patterns={"^aai%-loader$","^basic%-loader$"}
    },
    {
      change=0.05,
      items={"fast-transport-belt","fast-underground-belt","fast-splitter","fast-loader","aai-fast-loader"},
      item_patterns={"^.+%-fast%-loader$"}
    },
    {
      change=0.02,
      items={
        "express-transport-belt",
        "express-underground-belt",
        "express-splitter",
        "express-loader",
        "aai-express-loader"
      },
      item_patterns={"^.+%-express%-loader$"}
    },
    {
      change=0.01,
      items={
        "turbo-transport-belt",
        "turbo-underground-belt",
        "turbo-splitter",
        "turbo-loader",
        "aai-turbo-loader"
      },
      item_patterns={
        "^turbo%-transport%-belt$",
        "^turbo%-underground%-belt$",
        "^turbo%-splitter$",
        "^.+%-turbo%-loader$"
      }
    },
    {
      change=0.005,
      items={
        "hyper-transport-belt",
        "hyper-underground-belt",
        "hyper-splitter",
        "hyper-loader",
        "aai-hyper-loader"
      },
      item_patterns={
        "^hyper%-transport%-belt$",
        "^hyper%-underground%-belt$",
        "^hyper%-splitter$",
        "^.+%-hyper%-loader$"
      }
    }
  }},

  research_inserters = { icon_tech="fast-inserter", groups = {
    { change=0.10, items={"inserter","burner-inserter"} },
    { change=0.05, items={"fast-inserter","long-handed-inserter"} },
    { change=0.02, items={"bulk-inserter"}, item_patterns={"bulk%-inserter"} },
    { change=0.01, items={"stack-inserter"}, item_patterns={"stack%-inserter"} }
  }},

  research_science_pack_productivity = {
    icon_candidates={
      {technology="research-productivity", required_mod="space-age"},
      {icon="__space-age__/graphics/technology/research-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="space-science-pack"},
      {item="automation-science-pack"}
    },
    dynamic_items_from_lab_inputs = true,
    groups = {
    { change=0.10, items={
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "military-science-pack",
      "utility-science-pack",
      "space-science-pack",
      "agricultural-science-pack",
      "metallurgic-science-pack",
      "electromagnetic-science-pack",
      "cryogenic-science-pack",
      "promethium-science-pack"
    }}
  }}
}
