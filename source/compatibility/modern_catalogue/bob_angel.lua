-- Exact F200 Bob/Angel ordinary-catalogue delta. This declares only the
-- additive families and known recipe-vector replacements observed in the
-- pinned no-BobTech profile. Shared selection/collection remains outside this
-- file; it neither scans recipes nor selects an active profile.
local OVERLAY = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png"

local function effect(recipe, scale)
  return {recipe = recipe, scale = scale or 1}
end

local function tuning()
  return {
    base_cost = 8000,
    effect_percent = 10,
    enabled = true,
    growth_factor = 2,
    linear_increment = 0,
    max_level = 0,
    research_time = 60,
  }
end

return {
  -- Published ordinary science for this no-BobTech profile. Material stages
  -- have their own authored vectors and do not pass through this projection.
  science = {
    science_automation_logistic = "science_automation_logistic",
    science_automation_logistic_chemical_production = "science_automation_logistic",
    science_automation_logistic_chemical_production_military = "science_automation_logistic_military",
    science_automation_logistic_chemical_production_military_utility = "science_automation_logistic_military",
    science_automation_logistic_military_chemical_production_utility = "science_automation_logistic_military",
    science_utility_military = "science_military",
    science_automation_logistic_chemical_military_utility = "science_automation_logistic_military",
    science_automation_logistic_chemical_production_utility = "science_automation_logistic",
    science_automation_logistic_chemical_production_utility_military = "science_automation_logistic_military",
  },
  -- These direct continuations retain their explicit native gates instead
  -- of the ordinary recipe-derived water-treatment prerequisite.
  native_military_gates = {
    research_cannon_shooting_speed = true,
    research_electric_shooting_speed = true,
  },
  additions = {
    {
      key = "research_breeding",
      family = "research_breeding",
      kind = "productivity",
      science = "science_automation_logistic",
      prerequisites = {},
      effects = {
        effect("angels-alien-fish-0-raw"),
        effect("angels-biter-big-breeding"),
        effect("angels-biter-medium-breeding"),
        effect("angels-biter-small-breeding"),
        effect("angels-puffer-breeding-12"),
        effect("angels-puffer-breeding-13"),
        effect("angels-puffer-breeding-14"),
        effect("angels-puffer-breeding-15"),
        effect("angels-puffer-breeding-23"),
      },
      icon = "__base__/graphics/icons/fish.png",
      icon_size = 64,
      overlay = OVERLAY,
      localised_name = {
        "technology-name.more-infinite-research.research_breeding",
        {"technology-name.fish-breeding"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_breeding]",
      tuning = tuning(),
      setting_order = "b-050-breeding-productivity-stream-research_breeding-",
    },
    {
      key = "research_lithium",
      family = "research_lithium",
      kind = "productivity",
      science = "science_automation_logistic",
      prerequisites = {},
      effects = {effect("lithium-plate")},
      icon = "__base__/graphics/technology/mining-productivity.png",
      icon_size = 256,
      overlay = OVERLAY,
      localised_name = {
        "technology-name.more-infinite-research.research_lithium",
        {"technology-name.lithium-processing"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_lithium]",
      tuning = tuning(),
      setting_order = "b-100-lithium-productivity-stream-research_lithium-",
    },
    {
      key = "research_tungsten",
      family = "research_tungsten",
      kind = "productivity",
      science = "science_automation_logistic",
      prerequisites = {},
      effects = {
        effect("angels-plate-tungsten"),
        effect("tungsten-carbide"),
      },
      icon = "__angelssmeltinggraphics__/graphics/icons/plate-tungsten.png",
      icon_size = 32,
      overlay = OVERLAY,
      localised_name = {
        "technology-name.more-infinite-research.research_tungsten",
        {"item-name.tungsten-plate"},
      },
      localised_description = {"technology-description.more-infinite-research.recipe_productivity"},
      order = "p[research_tungsten]",
      tuning = tuning(),
      setting_order = "b-100-tungsten-productivity-stream-research_tungsten-",
    },
  },

  -- These replace named Base recipe vectors. Other ordinary targets stay with
  -- the shared product collector; this table does not infer alternatives.
  definition_overrides = {
    research_advanced_circuit = {icon="__bobelectronics__/graphics/icons/technology/advanced-electronics.png", icon_size=128},
    research_copper = {icon="__angelssmeltinggraphics__/graphics/icons/plate-copper.png", icon_size=32,
      effects={effect("angels-plate-copper"), effect("angels-plate-copper-2"), effect("copper-plate")}},
    research_copper_cable = {icon="__angelssmeltinggraphics__/graphics/icons/wire-copper.png", icon_size=32,
      effects={effect("angels-wire-copper-2"), effect("copper-cable")}},
    research_iron = {icon="__angelssmeltinggraphics__/graphics/icons/plate-iron.png", icon_size=32,
      effects={effect("angels-plate-iron"), effect("angels-plate-iron-2"), effect("iron-plate")}},
    research_iron_sticks = {icon="__angelssmeltinggraphics__/graphics/icons/rod-iron.png", icon_size=32},
    research_processing_unit = {icon="__bobelectronics__/graphics/icons/technology/advanced-electronics-2.png", icon_size=128},
    -- Retain earned Base identities while the corresponding ordinary routes
    -- are replaced by this overhaul. Do not erase a save's earlier research.
    research_oil_processing_productivity = {available=false},
    research_oil_cracking_productivity = {available=false},
    research_concrete = {effects={
      effect("stone-brick"), effect("angels-concrete", 0.5), effect("concrete", 0.5),
      effect("hazard-concrete", 0.5), effect("refined-concrete", 0.2), effect("refined-hazard-concrete", 0.2),
    }},
    research_explosives = {effects={
      effect("angels-solid-nitroglycerin"), effect("angels-solid-trinitrotoluene"), effect("explosives"),
    }},
    research_landfill = {effects={effect("angels-solid-mud-landfill"), effect("landfill")}},
    research_modules = {effects={
      effect("angels-bio-yield-module"), effect("efficiency-module"), effect("productivity-module"), effect("speed-module"),
      effect("angels-bio-yield-module-2", 0.5), effect("efficiency-module-2", 0.5),
      effect("productivity-module-2", 0.5), effect("speed-module-2", 0.5),
      effect("angels-bio-yield-module-3", 0.2), effect("efficiency-module-3", 0.2),
      effect("productivity-module-3", 0.2), effect("speed-module-3", 0.2),
    }},
    research_rockets = {effects={
      effect("rocket"), effect("explosive-rocket", 0.5), effect("angels-atomic-bomb", 0.2),
      effect("angels-atomic-bomb-2", 0.2), effect("atomic-bomb", 0.2),
    }},
    research_science_pack_productivity = {effects={
      effect("angels-desert-garden-a"), effect("angels-desert-garden-cultivating-a"),
      effect("angels-swamp-garden-a"), effect("angels-swamp-garden-cultivating-a"),
      effect("angels-temperate-garden-a"), effect("angels-temperate-garden-cultivating-a"),
      effect("automation-science-pack"), effect("chemical-science-pack"), effect("logistic-science-pack"),
      effect("military-science-pack"), effect("production-science-pack"), effect("utility-science-pack"),
    }},
    research_lubricant_productivity = {
      effects = {
        effect("angels-liquid-fish-oil-refining"),
        effect("angels-mineral-oil-lubricant"),
      },
    },
    research_plastic = {
      effects = {effect("angels-solid-plastic")},
    },
    research_steel = {
      effects = {
        effect("angels-plate-steel"),
        effect("angels-plate-steel-2"),
      },
    },
    research_sulfur = {
      effects = {
        effect("angels-solid-sodium-sulfate-separation"),
        effect("angels-solid-sulfur"),
        effect("angels-yellow-waste-water-purification"),
      },
    },
    research_sulfuric_acid_productivity = {
      effects = {effect("angels-liquid-sulfuric-acid")},
      -- The five native liquid layers plus the normal MIR productivity overlay
      -- are captured fields, rather than a guessed item icon substitution.
      icons = {
        {
          icon = "__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-base.png",
          icon_size = 330,
          scale = 0.09696969696969697,
          shift = {3.5, 0},
          tint = {a = 0.7, b = 0.25, g = 0.25, r = 0.25},
        },
        {
          icon = "__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-top.png",
          icon_size = 330,
          scale = 0.09696969696969697,
          shift = {3.5, 0},
          tint = {a = 1, b = 0.18823529411764706, g = 1, r = 1},
        },
        {
          icon = "__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-mid.png",
          icon_size = 330,
          scale = 0.09696969696969697,
          shift = {3.5, 0},
          tint = {a = 1, b = 0.9529411764705882, g = 0.9529411764705882, r = 0.9529411764705882},
        },
        {
          icon = "__angelsrefininggraphics__/graphics/icons/angels-liquid/liquid-item-bot.png",
          icon_size = 330,
          scale = 0.09696969696969697,
          shift = {3.5, 0},
          tint = {a = 1, b = 0.04313725490196079, g = 0.04313725490196079, r = 0.7764705882352941},
        },
        {
          icon = "__angelspetrochemgraphics__/graphics/icons/molecules/sulfuric-acid.png",
          icon_size = 72,
          scale = 0.20833333333333334,
          shift = {-10, -10},
        },
        {
          icon = OVERLAY,
          icon_size = 128,
          scale = 0.5,
          shift = {50, 50},
          floating = true,
        },
      },
    },
  },
}
