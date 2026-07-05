return {
  research_spoilage_preservation = {
    required_mods = {"space-age"},
    required_items = {"spoilage", "agricultural-science-pack"},
    icon_item = "spoilage",
    overlay = "speed",
    localised_description = {"technology-description.more-infinite-research.spoilage_preservation"},
    science_packs = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "space-science-pack",
      "agricultural-science-pack",
      "cryogenic-science-pack"
    },
    direct_effects = {
      {
        type = "nothing",
        effect_description = {"modifier-description.more-infinite-research.spoilage_preservation"}
      }
    }
  },

  research_agricultural_growth_speed = {
    required_mods = {"space-age"},
    required_items = {"agricultural-science-pack"},
    icon_tech = "agriculture",
    overlay = "speed",
    localised_description = {"technology-description.more-infinite-research.agricultural_growth_speed"},
    science_packs = {
      "automation-science-pack",
      "logistic-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "agricultural-science-pack",
      "electromagnetic-science-pack",
      "cryogenic-science-pack"
    },
    direct_effects = {
      {
        type = "nothing",
        effect_description = {"modifier-description.more-infinite-research.agricultural_growth_speed"}
      }
    }
  },

  research_inventory_capacity = {
    icon_tech = "toolbelt",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack"
    },
    direct_effects = {
      { type = "character-inventory-slots-bonus", modifier = 1 },
      { type = "character-logistic-trash-slots", modifier = 1 }
    }
  },

  research_robot_battery = {
    -- Better Bot Battery owns an infinite native worker-robot-battery chain
    -- with a different per-level value, so MIR cooperates instead of stacking.
    skip_if_technology_effects = {
      { technology = "worker-robots-battery-6", type = "worker-robot-battery", modifier = 0.70, max_level = "infinite" }
    },
    icon_tech = "logistic-robotics",
    direct_effects = {
      { type="worker-robot-battery", modifier=0.10 }
    }
  },

  research_lab_productivity = {
    -- Space Age and Research_Productivity already own native lab productivity.
    skip_if_technology_effects = {
      { technology = "research-productivity", type = "laboratory-productivity", max_level = "infinite" },
      { technology = "laboratory-productivity-4", type = "laboratory-productivity", modifier = 0.10, max_level = "infinite" }
    },
    icon_candidates = {
      {technology = "research-productivity", required_mod = "space-age"},
      {icon = "__space-age__/graphics/technology/research-productivity.png", icon_size = 256, inactive_mod_asset = "space-age"},
      {technology = "military-science-pack"}
    },
    overlay = "recipe-productivity",
    localised_description = {"technology-description.more-infinite-research.lab_productivity"},
    science_packs = {
      "automation-science-pack",
      "logistic-science-pack",
      "military-science-pack",
      "chemical-science-pack",
      "production-science-pack",
      "utility-science-pack",
      "space-science-pack"
    },
    direct_effects = {
      { type = "laboratory-productivity", modifier = 0.10 }
    }
  },

  research_cargo_bay_unloading_distance = {
    -- Cargo logistics modifiers are Space Age behavior even if another mod
    -- exposes similarly named cargo prototypes in a base-only run.
    required_mods = {"space-age"},
    required_items = {"landing-pad-unloading-bay"},
    required_technologies = {"landing-pad-unloading-bay"},
    icon_tech = "landing-pad-unloading-bay",
    overlay = "range",
    localised_description = {"technology-description.more-infinite-research.cargo_bay_unloading_distance"},
    science_packs = "all-official",
    direct_effects = {
      { type = "max-cargo-bay-unloading-distance", modifier = 10 }
    }
  },

  research_cargo_landing_pad_count = {
    -- Keep this Space Age-only; the startup setting can be enabled in any
    -- mod set, but generation must still skip without Space Age.
    required_mods = {"space-age"},
    required_items = {"cargo-landing-pad"},
    required_technologies = {"rocket-silo"},
    icon_tech = "space-platform",
    overlay = "count",
    localised_description = {"technology-description.more-infinite-research.cargo_landing_pad_count"},
    science_packs = "all-official",
    direct_effects = {
      { type = "cargo-landing-pad-count", modifier = 1 }
    }
  },

  research_rocket_shooting_speed = {
    icon_tech = "rocketry",
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "rocket", modifier = 0.1 }
    }
  },

  research_cannon_shooting_speed = {
    icon_item = "cannon-shell",
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.1 }
    }
  },

  research_flamethrower_shooting_speed = {
    icon_tech = "flamethrower",
    localised_description = {"technology-description.more-infinite-research.flamethrower_shooting_speed"},
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","space-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "flamethrower", modifier = 0.1 }
    }
  },

  research_electric_shooting_speed = {
    icon_candidates = {
      {technology = "electric-weapons-damage-1", required_mod = "space-age"},
      {icon = "__space-age__/graphics/technology/electric-weapons-damage.png", icon_size = 256, inactive_mod_asset = "space-age"},
      {technology = "discharge-defense-equipment"}
    },
    required_technologies = {"discharge-defense-equipment"},
    localised_description = {"technology-description.more-infinite-research.electric_shooting_speed"},
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","electromagnetic-science-pack"
    },
    direct_effects = {
      -- Space Age Tesla guns and Tesla turrets use the tesla ammo category.
      -- The older electric category covers discharge-defense equipment.
      { type = "gun-speed", ammo_category = "tesla", modifier = 0.1 },
      { type = "gun-speed", ammo_category = "electric", modifier = 0.1 }
    }
  },

  research_character_mining_speed = {
    icon = "__base__/graphics/technology/steel-axe.png",
    icon_size = 256,
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-mining-speed", modifier = 0.05 }
    }
  },

  research_character_crafting_speed = {
    icon_tech = "repair-pack",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-crafting-speed", modifier = 0.05 }
    }
  },

  research_character_walking_speed = {
    icon_item = "exoskeleton-equipment",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-running-speed", modifier = 0.05 }
    }
  },

  research_character_reach = {
    icon = "__base__/graphics/technology/steel-axe.png",
    icon_size = 256,
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "cryogenic-science-pack"
    },
    direct_effects = {
      { type = "character-reach-distance", modifier = 10 },
      { type = "character-build-distance", modifier = 10 },
      { type = "character-resource-reach-distance", modifier = 10 },
      { type = "character-item-drop-distance", modifier = 10 }
    }
  },

}
