return {
  research_inventory_capacity = {
    icon_tech = "toolbelt",
    science_packs = {
      "utility-science-pack","military-science-pack"
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
    -- Cooperate with another old-line mod that already owns an infinite
    -- native lab productivity chain.
    skip_if_technology_effects = {
      { technology = "research-productivity", type = "laboratory-productivity", max_level = "infinite" },
      { technology = "laboratory-productivity-4", type = "laboratory-productivity", modifier = 0.10, max_level = "infinite" }
    },
    icon_candidates = {
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
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack"
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
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack"
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
      {technology = "discharge-defense-equipment"}
    },
    required_technologies = {"discharge-defense-equipment"},
    localised_description = {"technology-description.more-infinite-research.electric_shooting_speed"},
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "electric", modifier = 0.1 }
    }
  },

  research_character_mining_speed = {
    icon_tech = "steel-axe",
    science_packs = {
      "utility-science-pack","military-science-pack"
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
      "utility-science-pack","military-science-pack"
    },
    direct_effects = {
      { type = "character-crafting-speed", modifier = 0.05 }
    }
  },

  research_character_walking_speed = {
    icon_tech = "exoskeleton-equipment",
    science_packs = {
      "utility-science-pack","military-science-pack"
    },
    direct_effects = {
      { type = "character-running-speed", modifier = 0.05 }
    }
  },

  research_character_reach = {
    icon_tech = "steel-axe",
    science_packs = {
      "utility-science-pack","military-science-pack"
    },
    direct_effects = {
      { type = "character-reach-distance", modifier = 10 },
      { type = "character-build-distance", modifier = 10 },
      { type = "character-resource-reach-distance", modifier = 10 },
      { type = "character-item-drop-distance", modifier = 10 }
    }
  },

}
