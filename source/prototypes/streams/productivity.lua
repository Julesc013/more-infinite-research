local overlay_loader = require("prototypes.mir.compatibility.overlay_loader")
local target_profiles = require("prototypes.mir.platform.factorio.target_profiles")
local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local material_progression = require("prototypes.mir.families.material_progression")

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

local function space_age_setting_visibility()
  return {
    mode = "visible-if-mods-any",
    mods_any = {"space-age"},
    hidden_reason = "space-age-not-active"
  }
end

local function native_owner_binding(owner, products)
  return {
    owner = owner,
    eligibility = {
      require_infinite = true,
      require_existing_recipe_productivity_effects = true
    },
    effect_scope = {
      type = "change-recipe-productivity",
      products = products
    },
    settings_ownership = "stream",
    default_preservation = "preserve-owner",
    override_policy = "recognized-cost-model",
    fallback_policy = "generate-eligible",
    cost_model = {
      target_native_formulas = {"1.5^L*1000"}
    }
  }
end

local native_owner_settings_note = {
  "mod-setting-description.mir-note-native-owner-managed-stream"
}

local streams = {
  research_copper = {
    items={"copper-plate"},
    icon_item="copper-plate",
    exclude_ingredient_patterns={"scrap"}
  },
  research_iron = {
    items={"iron-plate"},
    icon_item="iron-plate",
    exclude_ingredient_patterns={"scrap"}
  },
  research_steel = {
    items={"steel-plate"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/steel-plate-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="steel-processing"},
      {item="steel-plate"}
    },
    native_owner_binding = native_owner_binding("steel-plate-productivity", {"steel-plate"}),
    settings_note = native_owner_settings_note,
    exclude_ingredient_patterns={"scrap"}
  },
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
    native_owner_binding = native_owner_binding("processing-unit-productivity", {"processing-unit"}),
    settings_note = native_owner_settings_note
  },

  research_plastic = {
    items={"plastic-bar"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/plastics-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="plastics"}
    },
    native_owner_binding = native_owner_binding("plastic-bar-productivity", {"plastic-bar"}),
    settings_note = native_owner_settings_note
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
    native_owner_binding = native_owner_binding("low-density-structure-productivity", {"low-density-structure"}),
    settings_note = native_owner_settings_note
  },
  research_rocket_fuel = {
    items={"rocket-fuel"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/rocket-fuel-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="rocket-fuel"}
    },
    native_owner_binding = native_owner_binding("rocket-fuel-productivity", {"rocket-fuel"}),
    settings_note = native_owner_settings_note
  },

  research_thruster_fuel_productivity = {
    localised_name = {"technology-name.more-infinite-research.research_thruster_fuel_productivity"},
    ui_visibility = space_age_setting_visibility(),
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
    ui_visibility = space_age_setting_visibility(),
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
    allow_shared_input_output = true,
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
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"tungsten-plate", "tungsten-carbide"}
    },
    items={"tungsten-plate","tungsten-carbide"},
    icon_item="tungsten-plate",
    icon_tech="tungsten-processing"
  },
  research_lithium = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"lithium-plate", "lithium"}
    },
    icon_tech="lithium-processing",
    groups = {
    { change = 0.10, items = { "lithium-plate" } },
    { change = 0.05, items = { "lithium" }, recipe_patterns = { "^lithium$" } }
  } },
  research_holmium = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"holmium-plate"}
    },
    items={"holmium-plate"},
    icon_tech="holmium-processing"
  },
  research_supercapacitor = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"supercapacitor"}
    },
    items={"supercapacitor"},
    icon_tech="supercapacitor"
  },
  research_superconductor = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"superconductor"}
    },
    items={"superconductor"},
    icon_tech="superconductor"
  },
  research_quantum_processor = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"quantum-processor"}
    },
    items={"quantum-processor"},
    icon_tech="quantum-processor"
  },
  research_carbon = {
    ui_visibility = space_age_setting_visibility(),
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
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"carbon-fiber"}
    },
    items={"carbon-fiber"},
    icon_tech="carbon-fiber"
  },
  research_ice = {
    ui_visibility = space_age_setting_visibility(),
    required_mods = {"space-age"},
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
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item = {"bioflux"}
    },
    items={"bioflux"},
    icon_tech="bioflux"
  },
  research_bacteria_cultivation = {
    allow_shared_input_output = true,
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_recipe = {"iron-bacteria-cultivation", "copper-bacteria-cultivation"}
    },
    icon_tech = "bacteria-cultivation",
    recipe_patterns = {
    "^iron%-bacteria%-cultivation$",
    "^copper%-bacteria%-cultivation$"
  } },
  research_breeding = {
    allow_shared_input_output = true,
    -- Eligible breeding recipes may come from other mods without Space Age.
    -- Keep the existing controls visible; data-stage eligibility still owns
    -- whether research can be emitted on the target.
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
  research_nutrients = {
    localised_name = {"technology-name.more-infinite-research.research_nutrients"},
    ui_visibility = space_age_setting_visibility(),
    required_mods = {"space-age"},
    generation_requirements = {
      require_any_recipe = {
        "nutrients-from-yumako-mash",
        "nutrients-from-bioflux",
        "nutrients-from-biter-egg"
      }
    },
    groups = {
      {
        change = 0.10,
        recipe_patterns = {
          "^nutrients%-from%-yumako%-mash$",
          "^nutrients%-from%-bioflux$",
          "^nutrients%-from%-biter%-egg$"
        }
      }
    },
    icon_item = "nutrients"
  },
  research_capture_robot_rockets = {
    localised_name = {"technology-name.more-infinite-research.research_capture_robot_rockets"},
    ui_visibility = space_age_setting_visibility(),
    required_mods = {"space-age"},
    generation_requirements = {
      require_any_recipe = {"capture-robot-rocket"}
    },
    productivity_permission_recipes = {
      {
        name = "capture-robot-rocket",
        required_mods = {"space-age"}
      }
    },
    groups = {
      {
        change = 0.10,
        recipe_patterns = {"^capture%-robot%-rocket$"}
      }
    },
    icon_item = "capture-robot-rocket",
    icon_tech = "captivity"
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

  research_platform = {
    required_mods = {"space-age"},
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_all_items = {"ice-platform", "space-platform-foundation"}
    },
    icon_item = "ice-platform",
    groups = {
      { change = 0.10, items = { "ice-platform" } },
      { change = 0.05, items = { "space-platform-foundation" } }
    },
    productivity_permission_recipes = {
    {
      name = "ice-platform",
      required_mods = {"space-age"}
    },
    {
      name = "space-platform-foundation",
      required_mods = {"space-age"}
    }
  } },

  research_artificial_soil = {
    ui_visibility = space_age_setting_visibility(),
    generation_requirements = {
      require_any_item_family = {"artificial-soil", "overgrowth-soil"}
    },
    icon_tech = "artificial-soil",
    groups = {
    { change = 0.10, item_patterns = { "^artificial%-.+%-soil$" } },
    { change = 0.05, item_patterns = { "^overgrowth%-.+%-soil$" } }
  } },

  research_molten_metals = {
    ui_visibility = space_age_setting_visibility(),
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
    { change = 0.02, items = { "foundry", "industrial-furnace" }, item_patterns = { "^foundry$" } }
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
    { change=0.05, items={"advanced-solar","advanced-accumulator","se-space-solar-panel","se-space-accumulator","solar-matrix","accumulator-v2"} },
    { change=0.02, items={"elite-solar","elite-accumulator","se-space-solar-panel-2","se-space-accumulator-2"} },
    { change=0.01, items={"ultimate-solar","ultimate-accumulator","se-space-solar-panel-3"} }
  } },

  research_bullets = { icon_tech="military", groups = {
    { change=0.10, items={"firearm-magazine","shotgun-shell","bob-bullet-magazine","bob-better-shotgun-shell"} },
    { change=0.05, items={"piercing-rounds-magazine","piercing-shotgun-shell","bob-ap-bullet-magazine","bob-shotgun-ap-shell"} },
    { change=0.02, items={"uranium-rounds-magazine","uranium-shotgun-shell","bob-shotgun-uranium-shell"} },
    { change=0.01, items={
      "bob-he-bullet-magazine","bob-flame-bullet-magazine","bob-acid-bullet-magazine",
      "bob-poison-bullet-magazine","bob-electric-bullet-magazine","bob-plasma-bullet-magazine",
      "bob-shotgun-electric-shell","bob-shotgun-explosive-shell","bob-shotgun-flame-shell",
      "bob-shotgun-acid-shell","bob-shotgun-poison-shell","bob-shotgun-plasma-shell"
    }, item_patterns={
      "^plutonium%-.+magazine$","^plutonium%-.+shotgun%-shell$",
      "^tungsten%-.+magazine$","^tungsten%-.+shotgun%-shell$"
    } }
  }},

  research_heavy_ammo = { icon_item="cannon-shell", groups = {
    { change=0.10, items={"cannon-shell"} },
    { change=0.05, items={"explosive-cannon-shell"} },
    { change=0.02, items={"uranium-cannon-shell","explosive-uranium-cannon-shell"} },
    { change=0.01, items={
      "artillery-shell","railgun-ammo","bob-scatter-cannon-shell","bob-poison-artillery-shell",
      "bob-fire-artillery-shell","bob-explosive-artillery-shell","bob-distractor-artillery-shell",
      "bob-atomic-artillery-shell"
    }, item_patterns={
      "^.+%-cannon%-shell$","^.+%-artillery%-shell$","^.+%-railgun%-ammo$"
    } }
  }},

  research_rockets = { icon_tech="rocketry", groups = {
    { change=0.10, items={"rocket","bob-rocket"} },
    { change=0.05, items={"explosive-rocket","bob-explosive-rocket"} },
    { change=0.02, items={"atomic-bomb"} },
    { change=0.01, items={
      "plutonium-bomb","bob-piercing-rocket","bob-electric-rocket","bob-acid-rocket",
      "bob-flame-rocket","bob-poison-rocket","bob-plasma-rocket"
    }, item_patterns={"^plutonium%-bomb$","^plutonium%-.+bomb$"} }
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
    { change=0.10, module_tiers={1} },
    { change=0.05, module_tiers={2} },
    { change=0.02, module_tiers={3} },
    { change=0.01, module_tier_min=4 }
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
    },
    {
      change=0.005,
      structural_fallback=true,
      place_result_entity_types={
        "transport-belt",
        "underground-belt",
        "splitter",
        "lane-splitter",
        "loader",
        "loader-1x1"
      },
      reject_explicit_productivity_denial=true
    }
  }},

  research_inserters = { icon_tech="fast-inserter", groups = {
    { change=0.10, items={"inserter","burner-inserter"} },
    { change=0.05, items={"fast-inserter","long-handed-inserter"} },
    { change=0.02, items={"bulk-inserter"}, item_patterns={"bulk%-inserter"} },
    { change=0.01, items={"stack-inserter"}, item_patterns={"stack%-inserter"} },
    {
      change=0.01,
      structural_fallback=true,
      place_result_entity_types={"inserter"},
      reject_explicit_productivity_denial=true
    }
  }},

  research_auto_assembling_machine = {
    manifest_id = "mir-auto-prod-manufacturing-assembling-machine-1",
    technology_name = "mir-auto-prod-manufacturing-assembling-machine-1",
    identity_state = "released",
    automatic_family = {creation_maturity = "experimental"},
    localised_name = {"", "Assembling machine manufacturing productivity"},
    icon_item = "assembling-machine-3",
    science_packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    groups = {{change = 0.02, items = {}}}
  },

  research_auto_lab = {
    manifest_id = "mir-auto-prod-manufacturing-lab-1",
    technology_name = "mir-auto-prod-manufacturing-lab-1",
    identity_state = "released",
    automatic_family = {creation_maturity = "experimental"},
    localised_name = {"", "Lab manufacturing productivity"},
    icon_item = "lab",
    science_packs = {"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"},
    groups = {{change = 0.02, items = {}}}
  },

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


local function material_family(item, routes, mod_names, display_item)
  display_item = display_item or item
  return {
    required_items = {item},
    icon_item = display_item,
    localised_name = {"", {"description.productivity-bonus"}, ": ", {"item-name." .. display_item}},
    ui_visibility = {mode = "visible-if-mods-any", mods_any = mod_names, hidden_reason = "material-ecosystem-not-active"},
    identity_state = "stable-unreleased",
    science_packs = "derive-from-unlocks",
    prerequisites = "derive-from-unlocks",
    base_cost = 200,
    growth_factor = 2,
    research_time = 30,
    max_level = 3,
    require_acyclic_process = true,
    groups = {{change = 0.02, recipe_patterns = exact_recipe_patterns(routes), reject_explicit_productivity_denial = true}}
  }
end

-- The additional Angel final routes in this batch have one exact F200
-- combined-world observation. Keep every other F200 closure, and F210, on
-- their established declarations until each has its own ordering and engine
-- case qualified. These are the same product and observer locks that bind the
-- reviewed Nickel and Silver certificates below.
local F200_BOB_ANGEL_MATERIAL_LOCK = {
  base="2.0.77", boblibrary="2.1.0", bobores="2.1.2", bobplates="2.1.1",
  bobelectronics="2.1.1", bobtech="2.1.0", angelsrefining="2.0.4",
  angelsrefininggraphics="2.0.0", angelspetrochem="2.0.3",
  angelspetrochemgraphics="2.0.1", angelssmelting="2.0.5",
  angelssmeltinggraphics="2.0.0"
}

local F200_BOB_ANGEL_MATERIAL_OBSERVER_LOCKS = {
  ["mir-fixture-assert-f200-bob-angel-material-routes-observation"]="0.1.0",
  ["mir-fixture-assert-f200-science-researchability-diagnostic"]="0.1.0"
}

-- F210's current Bob/Angel set is a different recipe graph from the retained
-- F200 closure. Only Tin has an exact current-engine return witness so far;
-- keep every other F210 material on its existing declaration until its own
-- graph, binding, and unlock boundary is observed.
local F210_BOB_ANGEL_TIN_LOCK = {
  base="2.1.20", ["elevated-rails"]="2.1.20", quality="2.1.20",
  recycler="2.1.20", ["space-age"]="2.1.20", boblibrary="3.0.1",
  bobores="3.0.0", bobplates="3.0.2", bobelectronics="3.0.1",
  bobtech="3.0.0", angelsrefining="2.1.2", angelsrefininggraphics="2.1.0",
  angelspetrochem="2.1.3", angelspetrochemgraphics="2.1.0",
  angelssmelting="2.1.1", angelssmeltinggraphics="2.1.1"
}

local F210_BOB_ANGEL_TIN_OBSERVER_LOCKS = {
  ["mir-fixture-assert-f210-current-bob-angel-tin-route-observer"]="0.1.0"
}

-- This profile chooses the observed F200 final-route declarations.  An
-- extension is allowed through declaration only; each route must still match
-- its own complete typed return graph and ownership/unlock boundary below.
-- Schema-1 certificates retain their recorded provider set. Additional mods
-- require recaptured schema-2 cone-wide bindings, even if the added recipes
-- are disconnected; declaration alone does not authorize their emission.
local function f200_bob_angel_relevant_return_graph_profile()
  if target_profiles.current().factorio_version ~= "2.0" then return false end
  local active = mods or (script and script.active_mods)
  if type(active) ~= "table" then return false end
  for name, version in pairs(F200_BOB_ANGEL_MATERIAL_LOCK) do
    if active[name] ~= version then return false end
  end
  for name, version in pairs(F200_BOB_ANGEL_MATERIAL_OBSERVER_LOCKS) do
    if active[name] ~= nil and active[name] ~= version then return false end
  end
  return true
end

local f200_bob_angel_relevant_return_graph_routes = f200_bob_angel_relevant_return_graph_profile()

local function f210_bob_angel_tin_return_graph_profile()
  if target_profiles.current().factorio_version ~= "2.1" then return false end
  local active = mods or (script and script.active_mods)
  if type(active) ~= "table" then return false end
  for name, version in pairs(F210_BOB_ANGEL_TIN_LOCK) do
    if active[name] ~= version then return false end
  end
  for name, version in pairs(F210_BOB_ANGEL_TIN_OBSERVER_LOCKS) do
    if active[name] ~= nil and active[name] ~= version then return false end
  end
  return true
end

local f210_bob_angel_tin_return_graph_routes = f210_bob_angel_tin_return_graph_profile()

-- Gunmetal and Invar are the first F210 Bob/Angel final routes with an
-- observed empty return cone. Keep the profile exact: later routes with a
-- return edge need their own finalized boundary evidence.
local F210_BOB_ANGEL_GUNMETAL_INVAR_LOCK = {
  base="2.1.20", ["elevated-rails"]="2.1.20", quality="2.1.20",
  recycler="2.1.20", ["space-age"]="2.1.20", boblibrary="3.0.1",
  bobores="3.0.0", bobplates="3.0.2", bobelectronics="3.0.1",
  bobtech="3.0.0", angelsrefining="2.1.2", angelsrefininggraphics="2.1.0",
  angelspetrochem="2.1.3", angelspetrochemgraphics="2.1.0",
  angelssmelting="2.1.1", angelssmeltinggraphics="2.1.1"
}

local F210_BOB_ANGEL_GUNMETAL_INVAR_OBSERVER_LOCKS = {
  ["mir-fixture-assert-f210-current-bob-angel-final-routes-observer"]="0.1.0"
}

local function f210_bob_angel_gunmetal_invar_profile()
  if target_profiles.current().factorio_version ~= "2.1" then return false end
  local active = mods or (script and script.active_mods)
  if type(active) ~= "table" then return false end
  for name, version in pairs(F210_BOB_ANGEL_GUNMETAL_INVAR_LOCK) do
    if active[name] ~= version then return false end
  end
  for name, version in pairs(F210_BOB_ANGEL_GUNMETAL_INVAR_OBSERVER_LOCKS) do
    if active[name] ~= nil and active[name] ~= version then return false end
  end
  return true
end

local f210_bob_angel_gunmetal_invar_routes = f210_bob_angel_gunmetal_invar_profile()

local function f200_material_routes(existing, additions)
  local routes = {}
  for _, recipe in ipairs(existing) do routes[#routes + 1] = recipe end
  if f200_bob_angel_relevant_return_graph_routes then
    for _, recipe in ipairs(additions) do routes[#routes + 1] = recipe end
  end
  return routes
end

local function tin_material_routes()
  -- Bob's Tin recipe is hidden in this exact F210 profile. Declaring it
  -- alongside the two observed Angel finals would make the stream describe a
  -- non-player route, so select only the final routes proven below.
  if f210_bob_angel_tin_return_graph_routes then
    return {"angels-plate-tin", "angels-plate-tin-2"}
  end
  return f200_material_routes({"bob-tin-plate"}, {"angels-plate-tin", "angels-plate-tin-2"})
end

local function f210_gunmetal_invar_material_routes(existing, final_route)
  if f210_bob_angel_gunmetal_invar_routes then return {final_route} end
  return f200_material_routes(existing, {final_route})
end
-- Aluminium uses one stable technology identity, but the eligible final
-- manufacturing routes and the player-facing item differ by installed
-- ecosystem. The graph guard remains responsible for withholding unsafe or
-- hidden candidates in each final mod state.
local function aluminium_mod_active(name)
  return (mods and mods[name] ~= nil) or (script and script.active_mods and script.active_mods[name] ~= nil)
end

-- Stream declarations are also loaded by settings and control. Prototype
-- lookup is meaningful only during the data stage; retain the normal Bob
-- declaration whenever that stage is unavailable.
local function data_stage_item_prototype(name)
  if type(data) ~= "table" or type(data.extend) ~= "function" then return nil end
  if lookup.item_prototype("iron-plate") == nil then return nil end
  return lookup.item_prototype(name)
end

local function aluminium_material_family()
  if aluminium_mod_active("bobplates") and aluminium_mod_active("angelssmelting") then
    if not f200_bob_angel_relevant_return_graph_routes then
      return material_family("bob-aluminium-plate", {"bob-aluminium-plate"}, {"bobplates"})
    end
    return material_family("bob-aluminium-plate", {
      "bob-aluminium-plate",
      "angels-plate-aluminium",
      "angels-plate-aluminium-2"
    }, {"bobplates", "angelssmelting"})
  end
  if aluminium_mod_active("angelssmelting") then
    return material_family("angels-plate-aluminium", {
      "angels-plate-aluminium",
      "angels-plate-aluminium-2"
    }, {"angelssmelting"})
  end
  return material_family("bob-aluminium-plate", {"bob-aluminium-plate"}, {"bobplates"})
end

-- Gold, Platinum, and Silver use the pre-existing stable material technology
-- identities.  Angel-only wire is admitted only when Bob plates are absent,
-- so a plate-to-wire chain cannot collect two MIR productivity technologies.
-- The selected wire finals are the explicit Angel productivity-permitted
-- routes; direct wire and coolant-returning coil routes remain outside this
-- declaration and continue through the shared recipe safety guard.
local function bob_or_angel_wire_material_family(material)
  if aluminium_mod_active("angelssmelting") and not aluminium_mod_active("bobplates") then
    local item = "angels-wire-" .. material
    return material_family(item, {item .. "-2"}, {"angelssmelting"})
  end
  -- The exact F200 Bob/Angel lock removes Bob's Platinum plate entirely, but
  -- keeps Angel's ordinary, productivity-permitted final wire route. Select
  -- that one route only in this finalized shape. A present Bob plate always
  -- keeps the established Bob selection, and direct-wire and coil routes
  -- remain outside the declaration and the material-family graph guard.
  if material == "platinum"
    and f200_bob_angel_relevant_return_graph_routes
    and aluminium_mod_active("angelssmelting")
    and data_stage_item_prototype("bob-platinum-plate") == nil
    and data_stage_item_prototype("angels-wire-platinum") ~= nil then
    return material_family("angels-wire-platinum", {"angels-wire-platinum-2"}, {"bobplates", "angelssmelting"})
  end
  local routes = {"bob-" .. material .. "-plate"}
  if (material == "gold" or material == "silver")
    and f200_bob_angel_relevant_return_graph_routes then
    -- The finalized combined Bob/Angel profile makes Bob's plate through
    -- these ordinary Angel recipes; its Bob recipe is hidden in that profile.
    -- The exact, productivity-permitted wire final uses a distinct molten-wire
    -- coil input and the same unlock already represented by the plate finals.
    -- It therefore neither moves this stable material stream's stage nor
    -- applies a second effect to a plate-to-wire chain.
    routes[#routes + 1] = "angels-plate-" .. material
    routes[#routes + 1] = "angels-plate-" .. material .. "-2"
    routes[#routes + 1] = "angels-wire-" .. material .. "-2"
  end
  return material_family("bob-" .. material .. "-plate", routes, {"bobplates", "angelssmelting"})
end

-- Separate requested materials share policy, never translated-name matching.
streams.research_material_aluminium = aluminium_material_family()
streams.research_material_gold = bob_or_angel_wire_material_family("gold")
streams.research_material_lead = material_family("bob-lead-plate", f200_material_routes({"bob-lead-plate", "bob-lead-plate-2"}, {"angels-plate-lead", "angels-plate-lead-2"}), {"bobplates", "angelssmelting"})
streams.research_material_nickel = material_family("bob-nickel-plate", f200_bob_angel_relevant_return_graph_routes
  and {"bob-nickel-plate", "angels-plate-nickel", "angels-plate-nickel-2"}
  or f200_material_routes({"bob-nickel-plate"}, {"angels-plate-nickel", "angels-plate-nickel-2"}), {"bobplates", "angelssmelting"})
streams.research_material_platinum = bob_or_angel_wire_material_family("platinum")
streams.research_material_silver = bob_or_angel_wire_material_family("silver")
streams.research_material_tin = material_family("bob-tin-plate", tin_material_routes(), {"bobplates", "angelssmelting"})
streams.research_material_titanium = material_family("bob-titanium-plate", f200_material_routes({"bob-titanium-plate"}, {"angels-plate-titanium", "angels-plate-titanium-2"}), {"bobplates", "angelssmelting"})
streams.research_material_copper_tungsten = material_family("bob-copper-tungsten-alloy", {"bob-copper-tungsten-alloy"}, {"bobplates", "angelssmelting"})
streams.research_material_zinc = material_family("bob-zinc-plate", f200_material_routes({"bob-zinc-plate"}, {"angels-plate-zinc", "angels-plate-zinc-2"}), {"bobplates", "angelssmelting"})
streams.research_material_bronze = material_family("bob-bronze-alloy", f200_material_routes({"bob-bronze-alloy"}, {"angels-plate-bronze"}), {"bobplates", "angelssmelting"})
streams.research_material_brass = material_family("bob-brass-alloy", f200_material_routes({"bob-brass-alloy"}, {"angels-plate-brass"}), {"bobplates", "angelssmelting"})
streams.research_material_gunmetal = material_family("bob-gunmetal-alloy", f210_gunmetal_invar_material_routes({"bob-gunmetal-alloy"}, "angels-plate-gunmetal"), {"bobplates", "angelssmelting"})
streams.research_material_invar = material_family("bob-invar-alloy", f210_gunmetal_invar_material_routes({"bob-invar-alloy"}, "angels-plate-invar"), {"bobplates", "angelssmelting"})
streams.research_material_cobalt_steel = material_family("bob-cobalt-steel-alloy", f200_material_routes({"bob-cobalt-steel-alloy"}, {"angels-plate-cobalt-steel"}), {"bobplates", "angelssmelting"})
streams.research_material_nitinol = material_family("bob-nitinol-alloy", f200_material_routes({"bob-nitinol-alloy"}, {"angels-plate-nitinol"}), {"bobplates", "angelssmelting"})

-- These sixteen ordinary Bob/Angel families share one staged declaration.
for _, key in ipairs(material_progression.material_stream_keys()) do
  material_progression.attach(key, streams[key])
end

local function current_k2_213_material_profile()
  if target_profiles.current().factorio_version ~= "2.1" then return false end
  local active = mods or (script and script.active_mods)
  if type(active) ~= "table" then return false end
  -- Older target packages intentionally omit this 2.1-only policy.
  local k2_science_phase = require("prototypes.mir.compatibility.policies.k2_science_phase")
  for name, version in pairs(k2_science_phase.v3_applicability) do
    if active[name] ~= version then return false end
  end
  return true
end

-- RIC 0.36.1 Marine carbonisation is the one observed productivity-permitted
-- route without a recipe return path. The normal material graph and final
-- recipe permission still decide admission; Continental mode has no route.
streams.research_material_ric_coke = material_family("ric-coke", {"ric-carbonise-marine-biomass"}, {"real-industrial-chemistry"})
streams.research_material_ric_coke.localised_name = {"", {"description.productivity-bonus"}, ": ", {"recipe-name.ric-carbonise-marine-biomass"}}
streams.research_material_ric_coke.generation_requirements = {require_any_recipe = {"ric-carbonise-marine-biomass"}}

streams.research_material_rare_metals = material_family("kr-rare-metals", {"kr-rare-metals", "kr-rare-metals-from-enriched-rare-metals", "kr-casting-rare-metals"}, {"Krastorio2", "Krastorio2-spaced-out"})
-- K2SO's native owner retains crystal productivity. MIR owns the admitted
-- powder route, so present its generated technology as powder while keeping
-- crystal as the existing availability anchor.
streams.research_material_imersite = material_family("kr-imersite-crystal", {"kr-imersite-crystal", "kr-imersite-powder"}, {"Krastorio2", "Krastorio2-spaced-out"}, "kr-imersite-powder")
-- Only the current exact K2/K2SO tuple receives the MIR-owned powder
-- continuation. The separate native crystal owner remains untouched.
if current_k2_213_material_profile() then
  material_progression.attach_k2_213_continuation("research_material_imersite", streams.research_material_imersite)
end
streams.research_material_silicon = material_family("kr-silicon", {"kr-silicon"}, {"Krastorio2", "Krastorio2-spaced-out"})
streams.research_material_glass = material_family("kr-glass", {"kr-glass"}, {"Krastorio2", "Krastorio2-spaced-out"})
streams.research_material_black_paving = material_family("kr-black-reinforced-plate", {"kr-black-reinforced-plate"}, {"Krastorio2", "Krastorio2-spaced-out"})
streams.research_material_white_paving = material_family("kr-white-reinforced-plate", {"kr-white-reinforced-plate"}, {"Krastorio2", "Krastorio2-spaced-out"})
-- The other five requested K2 outcomes use the same owned-stage, science
-- and useful-headroom planner. Their original route admission remains the
-- authority, including withheld return paths and paving recolour exclusions.
for _, key in ipairs(material_progression.k2_material_stream_keys()) do
  material_progression.attach_k2_material_continuation(key, streams[key])
end
-- A10-reviewed forward-route certificates. These bind one exact final recipe,
-- one exact canonical risk fact, and one exact K2/K2SO runtime profile. They
-- are not a general exception to material-route graph safety.
local function k2_forward_profiles(risk_fingerprint)
  local common={base="2.1.17",["elevated-rails"]="2.1.17",quality="2.1.17",recycler="2.1.17",["space-age"]="2.1.17",flib="0.17.2",["k2so-assets"]="1.0.7",Krastorio2="2.1.2",Krastorio2Assets="2.1.0",Krastorio2MenuSimulations="2.1.0",["more-infinite-research"]="4.2.21000"}
  local locked={};for name, version in pairs(common) do locked[name]=version end
  locked["Krastorio2-spaced-out"]="2.0.13";locked["xy-k2so-enhancements-nulls-fork"]="0.8.3"
  local current={};for name, version in pairs(common) do current[name]=version end
  current["Krastorio2-spaced-out"]="2.0.17"
  local observers={["mir-validation-settings-overrides"]="0.1.0",["mir-fixture-assert-k2-materials"]="0.1.0"}
  return {{id="K2SO-2.0.13-with-xy",mod_locks=locked,observer_mod_locks=observers,canonical_risk_fingerprint=risk_fingerprint},{id="K2SO-2.0.17-without-xy",mod_locks=current,observer_mod_locks=observers,canonical_risk_fingerprint=risk_fingerprint}}
end
local function k2_forward_route(id, evidence_id, risk_fingerprint, ingredients, results)
  return {
    id=id,
    evidence_id=evidence_id,
    maximum_productivity=3.0,
    profiles=k2_forward_profiles(risk_fingerprint),
    ingredients=ingredients,
    results=results
  }
end
streams.research_material_rare_metals.reviewed_forward_routes = {
  ["kr-rare-metals"] = k2_forward_route("A10-K2-rare-metals-ore-v1","A05-K2-02-locked-current-v1","mir32-06ef774e",{{type="item",name="kr-rare-metal-ore",amount=2}},{{type="item",name="kr-rare-metals",amount=1}}),
  ["kr-rare-metals-from-enriched-rare-metals"] = k2_forward_route("A10-K2-rare-metals-enriched-v1","A05-K2-02-locked-current-v1","mir32-88e83d09",{{type="item",name="kr-enriched-rare-metals",amount=1}},{{type="item",name="kr-rare-metals",amount=1}})
}
streams.research_material_silicon.reviewed_forward_routes = {
  ["kr-silicon"] = k2_forward_route("A10-K2-silicon-v1","A05-K2-04-locked-current-v1","mir32-eb122be7",{{type="item",name="kr-quartz",amount=18}},{{type="item",name="kr-silicon",amount=9}})
}
streams.research_material_glass.reviewed_forward_routes = {
  ["kr-glass"] = k2_forward_route("A10-K2-glass-v1","A05-K2-05-locked-current-v1","mir32-a8a1f439",{{type="item",name="kr-sand",amount=16}},{{type="item",name="kr-glass",amount=8}})
}

-- Each ordinary final below is bound to its complete typed forward return
-- cone, direct finished-output producers, external owners, and unlock/science
-- facts observed in F200 2.0.77.  The certificate is intentionally required
-- even when the ordinary graph has no return path: that makes the declaration
-- safe to retain for a disconnected addition without treating a same-output
-- producer or a changed progression boundary as equivalent.
local function f200_bob_angel_return_graph_profile(risk_fingerprint)
  return {{
    id="F200-BobAngel-2.0.77-return-graph-final-v1",
    mod_locks=F200_BOB_ANGEL_MATERIAL_LOCK,
    observer_mod_locks=F200_BOB_ANGEL_MATERIAL_OBSERVER_LOCKS,
    mod_lock_scope="relevant-return-graph",
    canonical_risk_fingerprint=risk_fingerprint
  }}
end

local F200_BOB_ANGEL_BLOCKED_RETURN_WITNESSES = {
  {
    name="bob-silver-from-lead", hidden=true, enabled_without_research=false, source_class="hidden-internal",
    variants={{hidden=true, enabled=false,
      ingredients={{type="item",name="angels-solid-carbon",amount=3,probability=1,independent_probability=1},{type="item",name="bob-lead-oxide",amount=7,probability=1,independent_probability=1},{type="item",name="bob-nickel-plate",amount=1,probability=1,independent_probability=1}},
      results={{type="item",name="bob-lead-plate",amount_min=7,amount_max=11,probability=1,independent_probability=1},{type="item",name="bob-silver-ore",amount_min=1,amount_max=3,probability=1,independent_probability=1}}
    }}
  },
  {
    name="bob-silver-nitrate", hidden=true, enabled_without_research=false, source_class="hidden-internal",
    variants={{hidden=true, enabled=false,
      ingredients={{type="fluid",name="angels-gas-nitrogen-dioxide",amount=10,probability=1,independent_probability=1},{type="item",name="bob-silver-plate",amount=1,probability=1,independent_probability=1}},
      results={{type="item",name="bob-silver-nitrate",amount=1,probability=1,independent_probability=1}}
    }}
  }
}

local function f200_entry(kind, name, amount)
  return {type=kind, name=name, amount=amount}
end

-- The values are not a hand-derived recipe list.  They are the exact route,
-- typed return-graph, and progression fingerprints logged by the preserved
-- F200 final-data probe.  Counts keep a fingerprint-schema implementation
-- change from silently broadening the witness.
local F200_BOB_ANGEL_RETURN_GRAPH_ROUTES = {
  ["angels-plate-aluminium"]={risk="mir32-28583fe9",graph="mir32-1fde3ffa",bindings="mir32-bf1d1b0e",identities=72,recipes=74,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-aluminium",40)},results={f200_entry("item","bob-aluminium-plate",4)}},
  ["angels-plate-aluminium-2"]={risk="mir32-6ae1add6",graph="mir32-37eba2f4",bindings="mir32-d51a65ae",identities=72,recipes=74,producers=3,ingredients={f200_entry("item","angels-roll-aluminium",1)},results={f200_entry("item","bob-aluminium-plate",4)}},
  ["angels-plate-gold"]={risk="mir32-82b81bf5",graph="mir32-780bbbfa",bindings="mir32-d4567136",identities=70,recipes=75,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-gold",40)},results={f200_entry("item","bob-gold-plate",4)}},
  ["angels-plate-gold-2"]={risk="mir32-a5ba136b",graph="mir32-dec602a0",bindings="mir32-2f72d9cd",identities=70,recipes=75,producers=3,ingredients={f200_entry("item","angels-roll-gold",1)},results={f200_entry("item","bob-gold-plate",4)}},
  ["angels-wire-gold-2"]={id="F200-BA-gold-wire-final-v1",risk="mir32-f4af2099",graph="mir32-c4953ea9",bindings="mir32-f029b315",identities=68,recipes=72,producers=3,ingredients={f200_entry("item","angels-wire-coil-gold",4)},results={f200_entry("item","bob-gilded-copper-cable",16)}},
  ["angels-plate-lead"]={risk="mir32-c79c9256",graph="mir32-102b5dd2",bindings="mir32-d7313ff6",identities=198,recipes=207,producers=5,ingredients={f200_entry("fluid","angels-liquid-molten-lead",40)},results={f200_entry("item","bob-lead-plate",4)}},
  ["angels-plate-lead-2"]={risk="mir32-5ca75851",graph="mir32-f73c4d86",bindings="mir32-6b4b78ff",identities=198,recipes=207,producers=5,ingredients={f200_entry("item","angels-roll-lead",1)},results={f200_entry("item","bob-lead-plate",4)}},
  ["angels-plate-nickel"]={id="F200-BA-nickel-casting-v1",risk="mir32-b375a73e",graph="mir32-a27ea44e",bindings="mir32-ccf3ca93",identities=950,recipes=1488,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-nickel",40)},results={f200_entry("item","bob-nickel-plate",4)}},
  ["angels-plate-nickel-2"]={id="F200-BA-nickel-roll-v1",risk="mir32-d28043dc",graph="mir32-5f046c4a",bindings="mir32-3040c5f9",identities=950,recipes=1488,producers=3,ingredients={f200_entry("item","angels-roll-nickel",1)},results={f200_entry("item","bob-nickel-plate",4)}},
  ["angels-wire-platinum-2"]={risk="mir32-2f271ec9",graph="mir32-3869a68c",bindings="mir32-3e84abce",identities=27,recipes=28,producers=2,ingredients={f200_entry("item","angels-wire-coil-platinum",4)},results={f200_entry("item","angels-wire-platinum",16)}},
  ["angels-plate-tin"]={risk="mir32-42e8ee87",graph="mir32-0905b4fe",bindings="mir32-1a2afdfa",identities=207,recipes=214,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-tin",40)},results={f200_entry("item","bob-tin-plate",4)}},
  ["angels-plate-tin-2"]={risk="mir32-beddbea4",graph="mir32-3710fb19",bindings="mir32-2fbc823d",identities=207,recipes=214,producers=3,ingredients={f200_entry("item","angels-roll-tin",1)},results={f200_entry("item","bob-tin-plate",4)}},
  ["angels-plate-titanium"]={risk="mir32-b51c3afe",graph="mir32-2e5eac57",bindings="mir32-d8eb8681",identities=56,recipes=58,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-titanium",40)},results={f200_entry("item","bob-titanium-plate",4)}},
  ["angels-plate-titanium-2"]={risk="mir32-2addeacf",graph="mir32-84064d32",bindings="mir32-6a2e39c1",identities=56,recipes=58,producers=3,ingredients={f200_entry("item","angels-roll-titanium",1)},results={f200_entry("item","bob-titanium-plate",4)}},
  ["bob-copper-tungsten-alloy"]={risk="mir32-d92d266f",graph="mir32-cbb41f04",bindings="mir32-6951a533",identities=1,recipes=1,producers=1,ingredients={f200_entry("item","angels-powder-copper",10),f200_entry("item","bob-powdered-tungsten",15)},results={f200_entry("item","bob-copper-tungsten-alloy",25)}},
  ["angels-plate-zinc"]={risk="mir32-9a178c6f",graph="mir32-07cff5a5",bindings="mir32-8938e3e3",identities=43,recipes=45,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-zinc",40)},results={f200_entry("item","bob-zinc-plate",4)}},
  ["angels-plate-zinc-2"]={risk="mir32-d58ba53b",graph="mir32-39c69db5",bindings="mir32-be12e0f1",identities=43,recipes=45,producers=3,ingredients={f200_entry("item","angels-roll-zinc",1)},results={f200_entry("item","bob-zinc-plate",4)}},
  ["angels-plate-bronze"]={risk="mir32-fa8cecb5",graph="mir32-221a57b3",bindings="mir32-e5f8a5f0",identities=46,recipes=47,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-bronze",40)},results={f200_entry("item","bob-bronze-alloy",4)}},
  ["angels-plate-brass"]={risk="mir32-cbfc7d0e",graph="mir32-b0d7b6ab",bindings="mir32-3057c5da",identities=38,recipes=39,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-brass",40)},results={f200_entry("item","bob-brass-alloy",4)}},
  ["angels-plate-gunmetal"]={risk="mir32-df72e755",graph="mir32-989f026e",bindings="mir32-f5b0b17f",identities=1,recipes=2,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-gunmetal",40)},results={f200_entry("item","bob-gunmetal-alloy",4)}},
  ["angels-plate-invar"]={risk="mir32-85ae1247",graph="mir32-3790f90d",bindings="mir32-f6107c3a",identities=1,recipes=2,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-invar",40)},results={f200_entry("item","bob-invar-alloy",4)}},
  ["angels-plate-cobalt-steel"]={risk="mir32-b2a6ca58",graph="mir32-fb0f9f31",bindings="mir32-c79936f7",identities=38,recipes=39,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-cobalt-steel",40)},results={f200_entry("item","bob-cobalt-steel-alloy",4)}},
  ["angels-plate-nitinol"]={risk="mir32-e0fea025",graph="mir32-eba2f6d8",bindings="mir32-147c5076",identities=5,recipes=6,producers=2,ingredients={f200_entry("fluid","angels-liquid-molten-nitinol",40)},results={f200_entry("item","bob-nitinol-alloy",4)}},
  ["angels-plate-silver"]={id="F200-BA-silver-casting-v1",risk="mir32-fae4a0f7",graph="mir32-a77805c2",bindings="mir32-231b4067",identities=950,recipes=1488,producers=3,ingredients={f200_entry("fluid","angels-liquid-molten-silver",40)},results={f200_entry("item","bob-silver-plate",4)}},
  ["angels-plate-silver-2"]={id="F200-BA-silver-roll-v1",risk="mir32-a0f6b276",graph="mir32-f098b32a",bindings="mir32-c11b2eb5",identities=950,recipes=1488,producers=3,ingredients={f200_entry("item","angels-roll-silver",1)},results={f200_entry("item","bob-silver-plate",4)}},
  ["angels-wire-silver-2"]={id="F200-BA-silver-wire-final-v1",risk="mir32-ce67b188",graph="mir32-99c58542",bindings="mir32-53f936f8",identities=130,recipes=134,producers=2,ingredients={f200_entry("item","angels-wire-coil-silver",4)},results={f200_entry("item","angels-wire-silver",16)}}
}

local function f200_bob_angel_return_graph_route(recipe_name, relevant_input_contract)
  local observed = F200_BOB_ANGEL_RETURN_GRAPH_ROUTES[recipe_name]
  if not observed then error("MIR F200 missing return-graph observation " .. recipe_name) end
  return {
    id=observed.id or ("F200-BA-return-graph-" .. recipe_name .. "-v1"),
    evidence_id="F200-BobAngel-16Material-return-graph-2.0.77-v1",
    require_exact_route_certificate=true,
    maximum_productivity=3.0,
    profiles=f200_bob_angel_return_graph_profile(observed.risk),
    ingredients=observed.ingredients,
    results=observed.results,
    relevant_input_contract=relevant_input_contract,
    relevant_return_graph_contract={
      schema=1,
      return_graph_fingerprint=observed.graph,
      bindings_fingerprint=observed.bindings,
      reachable_identity_count=observed.identities,
      relevant_recipe_count=observed.recipes,
      direct_output_producer_count=observed.producers
    }
  }
end

local function f200_nickel_silver_input_contract(return_path, unlock_name, science_ingredients, prerequisites)
  return {
    productivity_owner_technologies={},
    return_path=return_path,
    return_witnesses=F200_BOB_ANGEL_BLOCKED_RETURN_WITNESSES,
    unlock_technologies={{name=unlock_name, science_ingredients=science_ingredients, prerequisites=prerequisites}}
  }
end

local function attach_f200_return_graph_routes(stream, recipes)
  local certificates = {}
  for _, recipe_name in ipairs(recipes) do
    certificates[recipe_name] = f200_bob_angel_return_graph_route(recipe_name)
  end
  stream.reviewed_forward_routes = certificates
end

if f200_bob_angel_relevant_return_graph_routes then
  attach_f200_return_graph_routes(streams.research_material_aluminium, {"angels-plate-aluminium", "angels-plate-aluminium-2"})
  attach_f200_return_graph_routes(streams.research_material_gold, {"angels-plate-gold", "angels-plate-gold-2", "angels-wire-gold-2"})
  attach_f200_return_graph_routes(streams.research_material_lead, {"angels-plate-lead", "angels-plate-lead-2"})
  attach_f200_return_graph_routes(streams.research_material_platinum, {"angels-wire-platinum-2"})
  attach_f200_return_graph_routes(streams.research_material_tin, {"angels-plate-tin", "angels-plate-tin-2"})
  attach_f200_return_graph_routes(streams.research_material_titanium, {"angels-plate-titanium", "angels-plate-titanium-2"})
  attach_f200_return_graph_routes(streams.research_material_copper_tungsten, {"bob-copper-tungsten-alloy"})
  attach_f200_return_graph_routes(streams.research_material_zinc, {"angels-plate-zinc", "angels-plate-zinc-2"})
  attach_f200_return_graph_routes(streams.research_material_bronze, {"angels-plate-bronze"})
  attach_f200_return_graph_routes(streams.research_material_brass, {"angels-plate-brass"})
  attach_f200_return_graph_routes(streams.research_material_gunmetal, {"angels-plate-gunmetal"})
  attach_f200_return_graph_routes(streams.research_material_invar, {"angels-plate-invar"})
  attach_f200_return_graph_routes(streams.research_material_cobalt_steel, {"angels-plate-cobalt-steel"})
  attach_f200_return_graph_routes(streams.research_material_nitinol, {"angels-plate-nitinol"})
  streams.research_material_nickel.reviewed_forward_routes = {
    ["angels-plate-nickel"] = f200_bob_angel_return_graph_route("angels-plate-nickel", f200_nickel_silver_input_contract("angels-liquid-molten-nickel", "angels-nickel-smelting-1", {{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}}, {"angels-metallurgy-2","angels-basic-chemistry-2"})),
    ["angels-plate-nickel-2"] = f200_bob_angel_return_graph_route("angels-plate-nickel-2", f200_nickel_silver_input_contract("angels-roll-nickel", "angels-nickel-casting-2", {{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},{name="chemical-science-pack",amount=1}}, {"angels-strand-casting-2","angels-nickel-smelting-1"}))
  }
  streams.research_material_silver.reviewed_forward_routes = {
    ["angels-plate-silver"] = f200_bob_angel_return_graph_route("angels-plate-silver", f200_nickel_silver_input_contract("angels-liquid-molten-silver", "angels-silver-smelting-1", {{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}}, {"angels-ore-floatation","angels-metallurgy-2"})),
    ["angels-plate-silver-2"] = f200_bob_angel_return_graph_route("angels-plate-silver-2", f200_nickel_silver_input_contract("angels-roll-silver", "angels-silver-casting-2", {{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1},{name="chemical-science-pack",amount=1}}, {"angels-strand-casting-2","angels-silver-smelting-1","angels-copper-casting-2"})),
    ["angels-wire-silver-2"] = f200_bob_angel_return_graph_route("angels-wire-silver-2")
  }
end

-- The exact 2.1.20 combined world has two visible Tin finals. Both graph
-- guards encounter a blocked return through the hidden Bronze recipe, so the
-- return endpoint, inactive variant, unlock science, and prerequisites are
-- bound as well as the typed graph fingerprint. This is intentionally
-- F210-Tin-only: it neither widens Bob-only/F200 behavior nor claims the
-- remaining Angel material families.
local F210_BOB_ANGEL_TIN_BLOCKED_RETURN_WITNESS = {
  {
    name="bob-bronze-alloy", hidden=true, enabled_without_research=false,
    source_class="hidden-internal",
    variants={{hidden=true, enabled=false,
      -- recipe_facts normalizes and sorts entries by type/name before the
      -- reviewed witness comparison, so bind that finalized order rather
      -- than Bobplates' source declaration order.
      ingredients={f200_entry("item","bob-tin-plate",2),f200_entry("item","copper-plate",3)},
      results={f200_entry("item","bob-bronze-alloy",5)}
    }}
  }
}

local F210_BOB_ANGEL_TIN_RETURN_GRAPH_ROUTES = {
  ["angels-plate-tin"]={
    id="F210-BA-tin-casting-final-v1", risk="mir32-42e8ee87",
    graph="mir32-60b04faf", bindings="mir32-1a2afdfa", identities=1039,
    recipes=2543, producers=8,
    ingredients={f200_entry("fluid","angels-liquid-molten-tin",40)},
    results={f200_entry("item","bob-tin-plate",4)},
    return_path="angels-liquid-molten-tin",
    unlock={name="angels-tin-smelting-1", science_ingredients={{name="automation-science-pack",amount=1}}, prerequisites={"angels-metallurgy-1"}}
  },
  ["angels-plate-tin-2"]={
    id="F210-BA-tin-roll-final-v1", risk="mir32-beddbea4",
    graph="mir32-5fc52628", bindings="mir32-2fbc823d", identities=1039,
    recipes=2543, producers=8,
    ingredients={f200_entry("item","angels-roll-tin",1)},
    results={f200_entry("item","bob-tin-plate",4)},
    return_path="angels-roll-tin",
    unlock={name="angels-tin-casting-2", science_ingredients={{name="automation-science-pack",amount=1},{name="logistic-science-pack",amount=1}}, prerequisites={"angels-copper-casting-2","angels-strand-casting-1","angels-tin-smelting-1"}}
  }
}

local function f210_bob_angel_tin_return_graph_profile(risk_fingerprint)
  return {{
    id="F210-BobAngel-2.1.20-Tin-return-graph-final-v1",
    mod_locks=F210_BOB_ANGEL_TIN_LOCK,
    observer_mod_locks=F210_BOB_ANGEL_TIN_OBSERVER_LOCKS,
    mod_lock_scope="relevant-return-graph",
    canonical_risk_fingerprint=risk_fingerprint
  }}
end

local function f210_bob_angel_tin_return_graph_route(recipe_name)
  local observed = F210_BOB_ANGEL_TIN_RETURN_GRAPH_ROUTES[recipe_name]
  if not observed then error("MIR F210 missing Tin return-graph observation " .. recipe_name) end
  return {
    id=observed.id,
    evidence_id="F210-BobAngel-Tin-return-graph-2.1.20-v1",
    require_exact_route_certificate=true,
    maximum_productivity=3.0,
    profiles=f210_bob_angel_tin_return_graph_profile(observed.risk),
    ingredients=observed.ingredients,
    results=observed.results,
    relevant_input_contract={
      productivity_owner_technologies={},
      return_path=observed.return_path,
      return_witnesses=F210_BOB_ANGEL_TIN_BLOCKED_RETURN_WITNESS,
      unlock_technologies={observed.unlock}
    },
    relevant_return_graph_contract={
      schema=1,
      return_graph_fingerprint=observed.graph,
      bindings_fingerprint=observed.bindings,
      reachable_identity_count=observed.identities,
      relevant_recipe_count=observed.recipes,
      direct_output_producer_count=observed.producers
    }
  }
end

if f210_bob_angel_tin_return_graph_routes then
  streams.research_material_tin.reviewed_forward_routes = {
    ["angels-plate-tin"] = f210_bob_angel_tin_return_graph_route("angels-plate-tin"),
    ["angels-plate-tin-2"] = f210_bob_angel_tin_return_graph_route("angels-plate-tin-2")
  }
end

-- The current F210 combined-world observation found no recipe return path
-- for these two finals. Bind the complete typed cone anyway: its binding
-- fingerprint covers the observed empty productivity-owner set and the exact
-- unlock boundary. A relevant-input contract would be false evidence here,
-- because that contract requires a real return path and hidden witness.
local F210_BOB_ANGEL_GUNMETAL_INVAR_RETURN_GRAPH_ROUTES = {
  ["angels-plate-gunmetal"]={
    id="F210-BA-gunmetal-final-v1", risk="mir32-df72e755",
    graph="mir32-d075395b", bindings="mir32-f5b0b17f", identities=1,
    recipes=3, producers=3,
    ingredients={f200_entry("fluid","angels-liquid-molten-gunmetal",40)},
    results={f200_entry("item","bob-gunmetal-alloy",4)}
  },
  ["angels-plate-invar"]={
    id="F210-BA-invar-final-v1", risk="mir32-85ae1247",
    graph="mir32-7cafb4f4", bindings="mir32-f6107c3a", identities=1,
    recipes=3, producers=3,
    ingredients={f200_entry("fluid","angels-liquid-molten-invar",40)},
    results={f200_entry("item","bob-invar-alloy",4)}
  }
}

local function f210_bob_angel_gunmetal_invar_return_graph_profile(risk_fingerprint)
  return {{
    id="F210-BobAngel-2.1.20-GunmetalInvar-return-graph-final-v1",
    mod_locks=F210_BOB_ANGEL_GUNMETAL_INVAR_LOCK,
    observer_mod_locks=F210_BOB_ANGEL_GUNMETAL_INVAR_OBSERVER_LOCKS,
    mod_lock_scope="relevant-return-graph",
    canonical_risk_fingerprint=risk_fingerprint
  }}
end

local function f210_bob_angel_gunmetal_invar_return_graph_route(recipe_name)
  local observed = F210_BOB_ANGEL_GUNMETAL_INVAR_RETURN_GRAPH_ROUTES[recipe_name]
  if not observed then error("MIR F210 missing Gunmetal/Invar return-graph observation " .. recipe_name) end
  return {
    id=observed.id,
    evidence_id="F210-BobAngel-GunmetalInvar-return-graph-2.1.20-v1",
    require_exact_route_certificate=true,
    maximum_productivity=3.0,
    profiles=f210_bob_angel_gunmetal_invar_return_graph_profile(observed.risk),
    ingredients=observed.ingredients,
    results=observed.results,
    relevant_return_graph_contract={
      schema=1,
      return_graph_fingerprint=observed.graph,
      bindings_fingerprint=observed.bindings,
      reachable_identity_count=observed.identities,
      relevant_recipe_count=observed.recipes,
      direct_output_producer_count=observed.producers
    }
  }
end

if f210_bob_angel_gunmetal_invar_routes then
  streams.research_material_gunmetal.reviewed_forward_routes = {
    ["angels-plate-gunmetal"] = f210_bob_angel_gunmetal_invar_return_graph_route("angels-plate-gunmetal")
  }
  streams.research_material_invar.reviewed_forward_routes = {
    ["angels-plate-invar"] = f210_bob_angel_gunmetal_invar_return_graph_route("angels-plate-invar")
  }
end

-- A06-reviewed Bob-only Aluminium route. This certificate is deliberately
-- narrower than the material family: it binds the one F210 official+Bob
-- profile observed after finalization, including the package-excluded
-- observer mods. Angel or combined profiles cannot match this lock.
local function bob_aluminium_forward_route()
  return {
    id="A06-Bob-Aluminium-F210-2.1.17-v1",
    evidence_id="A06-Bob-Aluminium-F210-locked-current-v1",
    maximum_productivity=3.0,
    profiles={{
      id="Bob-3.0.0-3.0.1-F210-2.1.17",
      mod_locks={base="2.1.17",["elevated-rails"]="2.1.17",quality="2.1.17",recycler="2.1.17",["space-age"]="2.1.17",["more-infinite-research"]="4.2.21000",boblibrary="3.0.0",bobores="3.0.0",bobplates="3.0.1"},
      observer_mod_locks={["mir-fixture-assert-a06-bob-aluminium-qualification"]="0.1.0",["mir-validation-settings-overrides"]="0.1.0"},
      canonical_risk_fingerprint="mir32-fd133af7"
    }},
    ingredients={{type="item",name="bob-alumina",amount=2},{type="item",name="carbon",amount=1}},
    results={{type="item",name="bob-aluminium-plate",amount=2}}
  }
end
if aluminium_mod_active("bobplates") and not aluminium_mod_active("angelssmelting") then
  streams.research_material_aluminium.reviewed_forward_routes = {
    ["bob-aluminium-plate"] = bob_aluminium_forward_route()
  }
end

-- Tin smelting is available initially on the exact Bob core lock.
streams.research_material_tin.science_packs = {"automation-science-pack"}

return streams
