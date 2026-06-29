return {
  research_inventory_capacity = {
    icon_tech = "toolbelt",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack"
    },
    direct_effects = {
      { type="character-inventory-slots-bonus", modifier=1 }
    }
  },

  research_robot_battery = { icon_tech = "logistic-robotics", direct_effects = {
    { type="worker-robot-battery", modifier=0.10 }
  } },

  research_cargo_bay_unloading_distance = {
    requires_space_age = true,
    required_items = {"landing-pad-unloading-bay"},
    required_technologies = {"landing-pad-unloading-bay"},
    icon_item = "landing-pad-unloading-bay",
    overlay = "range",
    localised_description = {"technology-description.more-infinite-research.cargo_bay_unloading_distance"},
    science_packs = "all",
    direct_effects = {
      { type = "max-cargo-bay-unloading-distance", modifier = 10 }
    }
  },

  research_cargo_landing_pad_count = {
    requires_space_age = true,
    required_items = {"cargo-landing-pad"},
    icon_item = "cargo-landing-pad",
    overlay = "count",
    localised_description = {"technology-description.more-infinite-research.cargo_landing_pad_count"},
    science_packs = "all",
    direct_effects = {
      { type = "cargo-landing-pad-count", modifier = 1 }
    }
  },

  research_rocket_shooting_speed = {
    icon_tech = "rocket-turret",
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","agricultural-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "rocket", modifier = 0.1 },
      { type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.1 }
    }
  },

  research_flamethrower_shooting_speed = {
    icon_tech = "flamethrower",
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","space-science-pack"
    },
    direct_effects = {
      { type = "gun-speed", ammo_category = "flamethrower", modifier = 0.1 }
    }
  },

  research_electric_shooting_speed = {
    requires_space_age = true,
    icon_tech = "tesla-weapons",
    required_technologies = {"tesla-weapons"},
    required_ammo_categories = {"electric"},
    science_packs = {
      "automation-science-pack","logistic-science-pack","chemical-science-pack",
      "production-science-pack","military-science-pack","electromagnetic-science-pack"
    },
    direct_effects = {
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
    requires_space_age = true,
    icon = "__space-age__/graphics/technology/health.png",
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

  research_character_trash_slots = {
    icon_tech = "toolbelt",
    science_packs = {
      "utility-science-pack","military-science-pack","agricultural-science-pack"
    },
    direct_effects = {
      { type = "character-logistic-trash-slots", modifier = 1 }
    }
  }
}
