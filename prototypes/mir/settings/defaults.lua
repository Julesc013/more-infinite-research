local defaults = {
  -- Global defaults used when a stream does not provide an override here or in its definition.
  shared = {
    enabled = true,
    base_cost = 8000,
    growth_factor = 2,
    max_level = 0, -- 0 or nil => infinite
    research_time = 60
  },
  -- Per-stream overrides. Add, remove, or modify entries as needed.
  streams = {
    research_inventory_capacity = { growth_factor = 1.10 },
    research_robot_battery = { growth_factor = 1.2 },
    research_lab_productivity = {
      base_cost = 1000,
      growth_factor = 1.2,
      research_time = 120,
      max_level = 0,
      settings_priority = "top"
    },
    research_ash_separation = {
      research_time = 90
    },
    research_science_pack_productivity = {
      research_time = 120
    },
    research_character_reach = {
      enabled = true,
      settings_priority = "top"
    },
    research_rocket_shooting_speed = {
      base_cost = 60,
      growth_factor = 1.5,
      science_packs = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "electromagnetic-science-pack"
      }
    },
    research_cannon_shooting_speed = {
      base_cost = 60,
      growth_factor = 1.5,
      science_packs = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "electromagnetic-science-pack"
      }
    },
    research_flamethrower_shooting_speed = {
      base_cost = 60,
      growth_factor = 1.5,
      science_packs = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "space-science-pack"
      }
    },
    research_electric_shooting_speed = {
      base_cost = 60,
      growth_factor = 1.5,
      science_packs = {
        "automation-science-pack",
        "logistic-science-pack",
        "chemical-science-pack",
        "production-science-pack",
        "military-science-pack",
        "electromagnetic-science-pack"
      }
    }
  },
  -- Extension overrides for base-game technologies.
  base_extensions = {
    ["braking-force"] = {
      enabled = true,
      settings_priority = "top",
      max_level = 0,
      base_cost = 115,
      growth_factor = 1.333333333333,
      research_time = 60,
      science_packs = "inherit",
      add_science_packs = {
        "space-science-pack"
      }
    },
    ["research-speed"] = {
      enabled = true,
      settings_priority = "top",
      max_level = 0,
      base_cost = 60,
      growth_factor = 1.5,
      research_time = 120,
      science_packs = "inherit",
      add_science_packs = "all"
    },
    ["worker-robots-storage"] = {
      enabled = true,
      settings_priority = "top",
      max_level = 0,
      base_cost = 200,
      growth_factor = 1.5,
      research_time = 60,
      science_packs = "inherit",
      add_science_packs = {
        "electromagnetic-science-pack"
      }
    },
    ["inserter-capacity-bonus"] = {
      enabled = false,
      settings_priority = "top",
      max_level = 0,
      base_cost = 200,
      growth_factor = 3.333333333333,
      research_time = 60,
      non_bulk_increment = 2,
      bulk_increment = 4,
      settings_note = {
        "mod-setting-description.mir-note-inserter-capacity"
      },
      science_packs = "inherit",
      add_science_packs = {
        "agricultural-science-pack"
      }
    },
    ["weapon-shooting-speed"] = {
      enabled = true,
      settings_priority = "top",
      max_level = 0,
      base_cost = 60,
      growth_factor = 1.5,
      research_time = 120,
      science_packs = "inherit",
      add_science_packs = {
        "military-science-pack",
        "space-science-pack"
      }
    },
    ["laser-shooting-speed"] = {
      enabled = true,
      settings_priority = "top",
      chain_key = "laser-turret-speed",
      generated_key = "laser-turret-speed",
      max_level = 0,
      base_cost = 60,
      growth_factor = 1.5,
      research_time = 120,
      science_packs = "inherit",
      add_science_packs = {
        "military-science-pack",
        "space-science-pack"
      }
    }
  }
}

return defaults
