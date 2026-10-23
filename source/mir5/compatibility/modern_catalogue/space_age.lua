-- Exact F210 Space Age deltas. This body is loaded only after the active
-- profile proves Space Age; Base stages never construct these mappings.
return {
  omit = {
    "research_lab_productivity",
    "research_low_density_structure",
    "research_plastic",
    "research_processing_unit",
    "research_rocket_fuel",
    "research_steel",
  },
  additions = {
    {
      key = "research_artificial_soil",
      family = "research_artificial_soil",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural_space",
      prerequisites = {},
      effects = {
        {
          recipe = "artificial-jellynut-soil",
          scale = 1,
        },
        {
          recipe = "artificial-yumako-soil",
          scale = 1,
        },
        {
          recipe = "overgrowth-jellynut-soil",
          scale = 0.5,
        },
        {
          recipe = "overgrowth-yumako-soil",
          scale = 0.5,
        },
      },
      icon = "__space-age__/graphics/technology/artificial-soil.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_artificial_soil",
        {"technology-name.artificial-soil"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_artificial_soil]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-artificial-soil-productivity-stream-research_artificial_soil-",
    },
    {
      key = "research_bacteria_cultivation",
      family = "research_bacteria_cultivation",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "copper-bacteria-cultivation",
          scale = 1,
        },
        {
          recipe = "iron-bacteria-cultivation",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/bacteria-cultivation.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_bacteria_cultivation",
        {"technology-name.bacteria-cultivation"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_bacteria_cultivation]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-bacteria-cultivation-productivity-stream-research_bacteria_cultivation-",
    },
    {
      key = "research_bioflux",
      family = "research_bioflux",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural",
      prerequisites = {},
      effects = {
        {
          recipe = "bioflux",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/bioflux.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_bioflux",
        {"item-name.bioflux"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_bioflux]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-bioflux-productivity-stream-research_bioflux-",
    },
    {
      key = "research_breeding",
      family = "research_breeding",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "biter-egg",
          scale = 1,
        },
        {
          recipe = "fish-breeding",
          scale = 1,
        },
        {
          recipe = "pentapod-egg",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/fish-breeding.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_breeding",
        {"technology-name.fish-breeding"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_breeding]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-050-breeding-productivity-stream-research_breeding-",
    },
    {
      key = "research_capture_robot_rockets",
      family = "research_capture_robot_rockets",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_military_agricultural",
      prerequisites = {},
      effects = {
        {
          recipe = "capture-robot-rocket",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/captivity.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {"technology-name.more-infinite-research.research_capture_robot_rockets"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_capture_robot_rockets]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-capture-bot-rocket-productivity-stream-research_capture_robot_rockets-",
    },
    {
      key = "research_carbon",
      family = "research_carbon",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_space",
      prerequisites = {},
      effects = {
        {
          recipe = "carbon",
          scale = 1,
        },
        {
          recipe = "burnt-spoilage",
          scale = 0.5,
        },
        {
          recipe = "coal-synthesis",
          scale = 0.2,
        },
      },
      icon = "__space-age__/graphics/icons/carbon.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_carbon",
        {"item-name.carbon"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_carbon]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-carbon-productivity-stream-research_carbon-",
    },
    {
      key = "research_carbon_fiber",
      family = "research_carbon_fiber",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural",
      prerequisites = {},
      effects = {
        {
          recipe = "carbon-fiber",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/carbon-fiber.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_carbon_fiber",
        {"item-name.carbon-fiber"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_carbon_fiber]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-carbon-fiber-productivity-stream-research_carbon_fiber-",
    },
    {
      key = "research_cargo_bay_unloading_distance",
      family = "research_cargo_bay_unloading_distance",
      kind = "direct",
      science = "science_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
      prerequisites = {"landing-pad-unloading-bay"},
      effects = {
        {
          raw = true,
          scale = 1,
          type = "max-cargo-bay-unloading-distance",
        },
      },
      icon = "__space-age__/graphics/technology/cargo-unloading-bay.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-range.png",
      localised_name = {
        "technology-name.more-infinite-research.research_cargo_bay_unloading_distance",
        {"technology-name.landing-pad-unloading-bay"},
      },
      localised_description = {"technology-description.more-infinite-research.cargo_bay_unloading_distance"},
      order = "p[research_cargo_bay_unloading_distance]",
      tuning = {
        base_cost = 100000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 3,
        linear_increment = 0,
        max_level = 0,
        research_time = 120,
      },
      setting_order = "b-050-cargo-bay-unloading-distance-stream-research_cargo_bay_unloading_distance-",
    },
    {
      key = "research_cargo_landing_pad_count",
      family = "research_cargo_landing_pad_count",
      kind = "direct",
      science = "science_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
      prerequisites = {"rocket-silo"},
      effects = {
        {
          raw = true,
          scale = 1,
          type = "cargo-landing-pad-count",
        },
      },
      icon = "__space-age__/graphics/technology/space-platform.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-count.png",
      localised_name = {
        "technology-name.more-infinite-research.research_cargo_landing_pad_count",
        {"technology-name.space-platform"},
      },
      localised_description = {"technology-description.more-infinite-research.cargo_landing_pad_count"},
      order = "p[research_cargo_landing_pad_count]",
      tuning = {
        base_cost = 1000000,
        effect_percent = 1,
        enabled = true,
        growth_factor = 10,
        linear_increment = 0,
        max_level = 0,
        research_time = 240,
      },
      setting_order = "b-050-cargo-landing-pad-count-stream-research_cargo_landing_pad_count-",
    },
    {
      key = "research_holmium",
      family = "research_holmium",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_electromagnetic",
      prerequisites = {},
      effects = {
        {
          recipe = "holmium-plate",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/holmium-processing.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_holmium",
        {"item-name.holmium-plate"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_holmium]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-holmium-productivity-stream-research_holmium-",
    },
    {
      key = "research_ice",
      family = "research_ice",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_space_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "ammoniacal-solution-separation",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/ice.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_ice",
        {"item-name.ice"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_ice]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-ice-productivity-stream-research_ice-",
    },
    {
      key = "research_lithium",
      family = "research_lithium",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "lithium-plate",
          scale = 1,
        },
        {
          recipe = "lithium",
          scale = 0.5,
        },
      },
      icon = "__space-age__/graphics/technology/lithium-processing.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_lithium",
        {"technology-name.lithium-processing"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_lithium]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-lithium-productivity-stream-research_lithium-",
    },
    {
      key = "research_molten_metals",
      family = "research_molten_metals",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_metallurgic",
      prerequisites = {},
      effects = {
        {
          recipe = "molten-copper-from-lava",
          scale = 1,
        },
        {
          recipe = "molten-iron-from-lava",
          scale = 1,
        },
        {
          recipe = "copper-ore-melting",
          scale = 0.5,
        },
        {
          recipe = "iron-ore-melting",
          scale = 0.5,
        },
      },
      icon = "__space-age__/graphics/technology/foundry.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_molten_metals",
        {"technology-name.foundry"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_molten_metals]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-molten-metals-productivity-stream-research_molten_metals-",
    },
    {
      key = "research_nutrients",
      family = "research_nutrients",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_agricultural_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "nutrients-from-bioflux",
          scale = 1,
        },
        {
          recipe = "nutrients-from-biter-egg",
          scale = 1,
        },
        {
          recipe = "nutrients-from-yumako-mash",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/nutrients.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {"technology-name.more-infinite-research.research_nutrients"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_nutrients]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-nutrients-productivity-stream-research_nutrients-",
    },
    {
      key = "research_platform",
      family = "research_platform",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_space_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "ice-platform",
          scale = 1,
        },
        {
          recipe = "space-platform-foundation",
          scale = 0.5,
        },
      },
      icon = "__space-age__/graphics/icons/ice-platform.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_platform",
        {"item-name.ice-platform"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_platform]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-platform-productivity-stream-research_platform-",
    },
    {
      key = "research_quantum_processor",
      family = "research_quantum_processor",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_cryogenic",
      prerequisites = {},
      effects = {
        {
          recipe = "quantum-processor",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/quantum-processor.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_quantum_processor",
        {"item-name.quantum-processor"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_quantum_processor]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-quantum-processor-productivity-stream-research_quantum_processor-",
    },
    {
      key = "research_science_pack_productivity",
      family = "research_science_pack_productivity",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_military_utility_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
      prerequisites = {},
      effects = {
        {
          recipe = "agricultural-science-pack",
          scale = 1,
        },
        {
          recipe = "automation-science-pack",
          scale = 1,
        },
        {
          recipe = "chemical-science-pack",
          scale = 1,
        },
        {
          recipe = "cryogenic-science-pack",
          scale = 1,
        },
        {
          recipe = "electromagnetic-science-pack",
          scale = 1,
        },
        {
          recipe = "logistic-science-pack",
          scale = 1,
        },
        {
          recipe = "metallurgic-science-pack",
          scale = 1,
        },
        {
          recipe = "military-science-pack",
          scale = 1,
        },
        {
          recipe = "production-science-pack",
          scale = 1,
        },
        {
          recipe = "promethium-science-pack",
          scale = 1,
        },
        {
          recipe = "space-science-pack",
          scale = 1,
        },
        {
          recipe = "utility-science-pack",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/technology/research-productivity.png",
      icon_size = 256,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {"technology-name.more-infinite-research.research_science_pack_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_science_pack_productivity]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 120,
      },
      setting_order = "b-100-science-pack-productivity-stream-research_science_pack_productivity-",
    },
    {
      key = "research_supercapacitor",
      family = "research_supercapacitor",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_electromagnetic",
      prerequisites = {},
      effects = {
        {
          recipe = "supercapacitor",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/supercapacitor.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_supercapacitor",
        {"item-name.supercapacitor"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_supercapacitor]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-supercapacitor-productivity-stream-research_supercapacitor-",
    },
    {
      key = "research_superconductor",
      family = "research_superconductor",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_electromagnetic",
      prerequisites = {},
      effects = {
        {
          recipe = "superconductor",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/superconductor.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_superconductor",
        {"item-name.superconductor"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_superconductor]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-superconductor-productivity-stream-research_superconductor-",
    },
    {
      key = "research_thruster_fuel_productivity",
      family = "research_thruster_fuel_productivity",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_space_agricultural",
      prerequisites = {},
      effects = {
        {
          recipe = "advanced-thruster-fuel",
          scale = 1,
        },
        {
          recipe = "thruster-fuel",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/fluid/thruster-fuel.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {"technology-name.more-infinite-research.research_thruster_fuel_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_thruster_fuel_productivity]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-thruster-fuel-productivity-stream-research_thruster_fuel_productivity-",
    },
    {
      key = "research_thruster_oxidizer_productivity",
      family = "research_thruster_oxidizer_productivity",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_space_agricultural",
      prerequisites = {},
      effects = {
        {
          recipe = "advanced-thruster-oxidizer",
          scale = 1,
        },
        {
          recipe = "thruster-oxidizer",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/fluid/thruster-oxidizer.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {"technology-name.more-infinite-research.research_thruster_oxidizer_productivity"},
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_thruster_oxidizer_productivity]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-thruster-oxidizer-productivity-stream-research_thruster_oxidizer_productivity-",
    },
    {
      key = "research_tungsten",
      family = "research_tungsten",
      kind = "productivity",
      science = "science_automation_logistic_chemical_production_metallurgic",
      prerequisites = {},
      effects = {
        {
          recipe = "tungsten-carbide",
          scale = 1,
        },
        {
          recipe = "tungsten-plate",
          scale = 1,
        },
      },
      icon = "__space-age__/graphics/icons/tungsten-plate.png",
      icon_size = 64,
      overlay = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png",
      localised_name = {
        "technology-name.more-infinite-research.research_tungsten",
        {"item-name.tungsten-plate"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_tungsten]",
      tuning = {
        base_cost = 8000,
        effect_percent = 10,
        enabled = true,
        growth_factor = 2,
        linear_increment = 0,
        max_level = 0,
        research_time = 60,
      },
      setting_order = "b-100-tungsten-productivity-stream-research_tungsten-",
    },
  },
  overrides = {
    research_advanced_circuit = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_batteries = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_belts = {
      science = "science_automation_logistic_chemical_production_space",
      effects = {
        {
          recipe = "splitter",
          scale = 1,
        },
        {
          recipe = "transport-belt",
          scale = 1,
        },
        {
          recipe = "underground-belt",
          scale = 1,
        },
        {
          recipe = "fast-splitter",
          scale = 0.5,
        },
        {
          recipe = "fast-transport-belt",
          scale = 0.5,
        },
        {
          recipe = "fast-underground-belt",
          scale = 0.5,
        },
        {
          recipe = "express-splitter",
          scale = 0.2,
        },
        {
          recipe = "express-transport-belt",
          scale = 0.2,
        },
        {
          recipe = "express-underground-belt",
          scale = 0.2,
        },
        {
          recipe = "turbo-splitter",
          scale = 0.1,
        },
        {
          recipe = "turbo-transport-belt",
          scale = 0.1,
        },
        {
          recipe = "turbo-underground-belt",
          scale = 0.1,
        },
      },
    },
    research_bullets = {
      science = "science_automation_logistic_chemical_production_military_space",
    },
    research_cannon_shooting_speed = {
      science = "science_automation_logistic_chemical_production_military_electromagnetic",
    },
    research_character_crafting_speed = {
      science = "science_utility_military_agricultural_electromagnetic",
    },
    research_character_mining_speed = {
      science = "science_utility_military_agricultural_electromagnetic",
    },
    research_character_reach = {
      science = "science_utility_military_agricultural_cryogenic",
    },
    research_character_walking_speed = {
      science = "science_utility_military_agricultural_electromagnetic",
    },
    research_concrete = {
      science = "science_automation_logistic_chemical_production_space",
      effects = {
        {
          recipe = "stone-brick",
          scale = 1,
        },
        {
          recipe = "concrete",
          scale = 0.5,
        },
        {
          recipe = "concrete-from-molten-iron",
          scale = 0.5,
        },
        {
          recipe = "hazard-concrete",
          scale = 0.5,
        },
        {
          recipe = "refined-concrete",
          scale = 0.2,
        },
        {
          recipe = "refined-hazard-concrete",
          scale = 0.2,
        },
      },
    },
    research_copper = {
      effects = {
        {
          recipe = "casting-copper",
          scale = 1,
        },
        {
          recipe = "copper-plate",
          scale = 1,
        },
      },
    },
    research_copper_cable = {
      effects = {
        {
          recipe = "casting-copper-cable",
          scale = 1,
        },
        {
          recipe = "copper-cable",
          scale = 1,
        },
      },
    },
    research_electric_energy = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_electric_engine = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_electric_shooting_speed = {
      science = "science_automation_logistic_chemical_production_military_electromagnetic",
      effects = {
        {
          ammo_category = "tesla",
          raw = false,
          scale = 1,
          type = "gun-speed",
        },
        {
          ammo_category = "electric",
          raw = false,
          scale = 1,
          type = "gun-speed",
        },
      },
      icon = "__space-age__/graphics/technology/electric-weapons-damage.png",
    },
    research_electronic_circuit = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_engine = {
      science = "science_automation_logistic_chemical_production_metallurgic",
    },
    research_explosives = {
      science = "science_automation_logistic_chemical_production_metallurgic",
    },
    research_flamethrower_shooting_speed = {
      science = "science_automation_logistic_chemical_production_military_space",
    },
    research_flying_robot_frame = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
    },
    research_furnace = {
      science = "science_automation_logistic_chemical_production_metallurgic",
      effects = {
        {
          recipe = "stone-furnace",
          scale = 1,
        },
        {
          recipe = "steel-furnace",
          scale = 0.5,
        },
        {
          recipe = "electric-furnace",
          scale = 0.25,
        },
        {
          recipe = "foundry",
          scale = 0.1,
        },
      },
    },
    research_grenades = {
      science = "science_automation_logistic_chemical_production_military_space",
    },
    research_heavy_ammo = {
      science = "science_automation_logistic_chemical_production_military_metallurgic_space",
      effects = {
        {
          recipe = "cannon-shell",
          scale = 1,
        },
        {
          recipe = "explosive-cannon-shell",
          scale = 0.5,
        },
        {
          recipe = "explosive-uranium-cannon-shell",
          scale = 0.2,
        },
        {
          recipe = "uranium-cannon-shell",
          scale = 0.2,
        },
        {
          recipe = "artillery-shell",
          scale = 0.1,
        },
        {
          recipe = "railgun-ammo",
          scale = 0.1,
        },
      },
    },
    research_inserters = {
      science = "science_automation_logistic_chemical_production_space",
      effects = {
        {
          recipe = "burner-inserter",
          scale = 1,
        },
        {
          recipe = "inserter",
          scale = 1,
        },
        {
          recipe = "fast-inserter",
          scale = 0.5,
        },
        {
          recipe = "long-handed-inserter",
          scale = 0.5,
        },
        {
          recipe = "bulk-inserter",
          scale = 0.2,
        },
        {
          recipe = "stack-inserter",
          scale = 0.1,
        },
      },
    },
    research_inventory_capacity = {
      science = "science_utility_military_agricultural",
    },
    research_iron = {
      effects = {
        {
          recipe = "casting-iron",
          scale = 1,
        },
        {
          recipe = "iron-plate",
          scale = 1,
        },
      },
    },
    research_iron_sticks = {
      effects = {
        {
          recipe = "casting-iron-stick",
          scale = 1,
        },
        {
          recipe = "iron-stick",
          scale = 1,
        },
      },
    },
    research_landfill = {
      science = "science_automation_logistic_chemical_production_metallurgic_space",
      effects = {
        {
          recipe = "landfill",
          scale = 1,
        },
        {
          recipe = "foundation",
          scale = 0.5,
        },
      },
    },
    research_lubricant_productivity = {
      science = "science_automation_logistic_chemical_production_electromagnetic",
      effects = {
        {
          recipe = "biolubricant",
          scale = 1,
        },
        {
          recipe = "lubricant",
          scale = 1,
        },
      },
    },
    research_mining_drill = {
      science = "science_automation_logistic_chemical_production_metallurgic",
      effects = {
        {
          recipe = "burner-mining-drill",
          scale = 1,
        },
        {
          recipe = "electric-mining-drill",
          scale = 0.5,
        },
        {
          recipe = "big-mining-drill",
          scale = 0.25,
        },
      },
    },
    research_modules = {
      science = "science_automation_logistic_chemical_production_cryogenic",
      effects = {
        {
          recipe = "efficiency-module",
          scale = 1,
        },
        {
          recipe = "productivity-module",
          scale = 1,
        },
        {
          recipe = "quality-module",
          scale = 1,
        },
        {
          recipe = "speed-module",
          scale = 1,
        },
        {
          recipe = "efficiency-module-2",
          scale = 0.5,
        },
        {
          recipe = "productivity-module-2",
          scale = 0.5,
        },
        {
          recipe = "quality-module-2",
          scale = 0.5,
        },
        {
          recipe = "speed-module-2",
          scale = 0.5,
        },
        {
          recipe = "efficiency-module-3",
          scale = 0.2,
        },
        {
          recipe = "productivity-module-3",
          scale = 0.2,
        },
        {
          recipe = "quality-module-3",
          scale = 0.2,
        },
        {
          recipe = "speed-module-3",
          scale = 0.2,
        },
      },
      icon = "__quality__/graphics/technology/module.png",
    },
    research_oil_cracking_productivity = {
      science = "science_automation_logistic_chemical_production_agricultural",
    },
    research_oil_processing_productivity = {
      science = "science_automation_logistic_chemical_production_cryogenic",
      effects = {
        {
          recipe = "advanced-oil-processing",
          scale = 1,
        },
        {
          recipe = "basic-oil-processing",
          scale = 1,
        },
        {
          recipe = "coal-liquefaction",
          scale = 1,
        },
        {
          recipe = "simple-coal-liquefaction",
          scale = 1,
        },
      },
    },
    research_rails = {
      science = "science_automation_logistic_chemical_production_space",
      effects = {
        {
          recipe = "rail",
          scale = 1,
        },
        {
          recipe = "rail-support",
          scale = 0.5,
        },
        {
          recipe = "rail-ramp",
          scale = 0.2,
        },
      },
      icon = "__elevated-rails__/graphics/technology/elevated-rail.png",
      icon_size = 256,
    },
    research_robot_battery = {
      science = "science_automation_logistic_chemical_production_space",
    },
    research_rocket_shooting_speed = {
      science = "science_automation_logistic_chemical_production_military_electromagnetic",
    },
    research_rockets = {
      science = "science_automation_logistic_chemical_production_agricultural_military",
    },
    research_sulfur = {
      science = "science_automation_logistic_chemical_production_metallurgic",
      effects = {
        {
          recipe = "biosulfur",
          scale = 1,
        },
        {
          recipe = "sulfur",
          scale = 1,
        },
      },
    },
    research_sulfuric_acid_productivity = {
      science = "science_automation_logistic_chemical_production_metallurgic",
      effects = {
        {
          recipe = "acid-neutralisation",
          scale = 1,
        },
        {
          recipe = "sulfuric-acid",
          scale = 1,
        },
      },
    },
    research_walls = {
      science = "science_automation_logistic_chemical_production_military_space",
    },
  },
  recipe_patches = {"capture-robot-rocket", "ice-platform", "space-platform-foundation"},
  continuation_overrides = {
    braking_force = {
      science = "science_automation_logistic_chemical_production_utility_space",
    },
    inserter_capacity_bonus = {
      science = "science_automation_logistic_chemical_production_utility_agricultural",
    },
    laser_shooting_speed = {
      science = "science_automation_logistic_chemical_military_utility_space",
    },
    research_speed = {
      science = "science_automation_logistic_chemical_production_utility_military_space_agricultural_metallurgic_electromagnetic_cryogenic_promethium",
    },
    weapon_shooting_speed = {
      science = "science_automation_logistic_chemical_military_utility_space",
    },
    worker_robots_storage = {
      science = "science_automation_logistic_chemical_production_utility_electromagnetic",
    },
  },
  native_owners = {
    {
      family = "research_low_density_structure",
      id = "low-density-structure-productivity",
      admission = {
        recipes = {"low-density-structure", "casting-low-density-structure"},
        effect_type = "change-recipe-productivity",
      },
      setting = "ips-max-level-research_low_density_structure",
    },
    {
      family = "research_plastic",
      id = "plastic-bar-productivity",
      admission = {
        recipes = {"plastic-bar", "bioplastic"},
        effect_type = "change-recipe-productivity",
      },
      setting = "ips-max-level-research_plastic",
    },
    {
      family = "research_processing_unit",
      id = "processing-unit-productivity",
      admission = {
        recipes = {"processing-unit"},
        effect_type = "change-recipe-productivity",
      },
      setting = "ips-max-level-research_processing_unit",
    },
    {
      family = "research_rocket_fuel",
      id = "rocket-fuel-productivity",
      admission = {
        recipes = {"rocket-fuel", "rocket-fuel-from-jelly", "ammonia-rocket-fuel"},
        effect_type = "change-recipe-productivity",
      },
      setting = "ips-max-level-research_rocket_fuel",
    },
    {
      family = "research_steel",
      id = "steel-plate-productivity",
      admission = {
        recipes = {"steel-plate", "casting-steel"},
        effect_type = "change-recipe-productivity",
      },
      setting = "ips-max-level-research_steel",
    },
  },
}
