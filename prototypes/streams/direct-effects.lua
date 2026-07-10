return {
  research_spoilage_preservation = {
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"spoilage", "agricultural-science-pack"}
    },
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
    ui_visibility = {
      mode = "always",
      reason = "official-stream-settings-visible"
    },
    generation_requirements = {
      require_any_item = {"agricultural-science-pack"}
    },
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
      {technology = "military-science-pack"},
      {technology = "mining-productivity-4"},
      {technology = "mining-productivity-3"},
      {technology = "mining-productivity-1"}
    },
    overlay = "laboratory-productivity",
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

  research_rocket_shooting_speed = {
    icon_tech = "rocketry",
    required_technologies = {"rocketry"},
    adopt_exact_native_effect_owner = true,
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "rocket", modifier = 0.1 }
    }
  },

  research_cannon_shooting_speed = {
    icon_candidates = {
      {technology = "weapon-shooting-speed-3"},
      {technology = "physical-projectile-damage-2"},
      {item = "cannon-shell"}
    },
    required_technologies = {"weapon-shooting-speed-5"},
    required_technology_candidates = {{"tank", "tanks"}},
    adopt_exact_native_effect_owner = true,
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
    required_technologies = {"flamethrower"},
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
    icon_tech = "steel-axe",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-mining-speed", modifier = 0.05 }
    }
  },

  research_character_crafting_speed = {
    icon_candidates = {
      {technology = "automation-3"},
      {technology = "automation-2"},
      {item = "repair-pack"}
    },
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-crafting-speed", modifier = 0.05 }
    }
  },

  research_character_walking_speed = {
    icon_tech = "exoskeleton-equipment",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack",
      "electromagnetic-science-pack"
    },
    direct_effects = {
      { type = "character-running-speed", modifier = 0.05 }
    }
  },

  research_character_reach = {
    icon_tech = "steel-axe",
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
