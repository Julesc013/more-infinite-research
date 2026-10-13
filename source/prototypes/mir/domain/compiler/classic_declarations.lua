-- The classic compiler deliberately supports a small, declared native core.
-- It does not discover recipes, science packs, ownership, or progression.

local M = {}

M.schema = 1

M.direct_streams = {
  research_inventory_capacity = {
    manifest_id = "research_inventory_capacity",
    technology_name = "recipe-prod-research_inventory_capacity-1",
    science = {
      "automation-science-pack", "logistic-science-pack", "military-science-pack",
      "chemical-science-pack", "production-science-pack", "utility-science-pack"
    },
    prerequisites = {"utility-science-pack"},
    effects = {
      {type = "character-inventory-slots-bonus", modifier = 1},
      {type = "character-logistic-trash-slots", modifier = 1}
    },
    cost = {base_cost = 8000, growth_factor = 1.1, research_time = 60},
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  },
  research_character_crafting_speed = {
    manifest_id = "research_character_crafting_speed",
    technology_name = "recipe-prod-research_character_crafting_speed-1",
    science = {
      "automation-science-pack", "logistic-science-pack", "military-science-pack",
      "chemical-science-pack", "production-science-pack", "utility-science-pack"
    },
    prerequisites = {"utility-science-pack"},
    effects = {{type = "character-crafting-speed", modifier = 0.05}},
    cost = {base_cost = 8000, growth_factor = 2, research_time = 60},
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  },
  research_character_mining_speed = {
    manifest_id = "research_character_mining_speed",
    technology_name = "recipe-prod-research_character_mining_speed-1",
    science = {
      "automation-science-pack", "logistic-science-pack", "military-science-pack",
      "chemical-science-pack", "production-science-pack", "utility-science-pack"
    },
    prerequisites = {"utility-science-pack"},
    effects = {{type = "character-mining-speed", modifier = 0.05}},
    cost = {base_cost = 8000, growth_factor = 2, research_time = 60},
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  },
  research_character_reach = {
    manifest_id = "research_character_reach",
    technology_name = "recipe-prod-research_character_reach-1",
    science = {
      "automation-science-pack", "logistic-science-pack", "military-science-pack",
      "chemical-science-pack", "production-science-pack", "utility-science-pack"
    },
    prerequisites = {"utility-science-pack"},
    effects = {
      {type = "character-reach-distance", modifier = 10},
      {type = "character-build-distance", modifier = 10},
      {type = "character-resource-reach-distance", modifier = 10},
      {type = "character-item-drop-distance", modifier = 10}
    },
    cost = {base_cost = 8000, growth_factor = 2, research_time = 60},
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  },
  research_character_walking_speed = {
    manifest_id = "research_character_walking_speed",
    technology_name = "recipe-prod-research_character_walking_speed-1",
    science = {
      "automation-science-pack", "logistic-science-pack", "military-science-pack",
      "chemical-science-pack", "production-science-pack", "utility-science-pack"
    },
    prerequisites = {"utility-science-pack"},
    effects = {{type = "character-running-speed", modifier = 0.05}},
    cost = {base_cost = 8000, growth_factor = 2, research_time = 60},
    icon = "__base__/graphics/technology/mining-productivity.png",
    icon_size = 256
  }
}

M.base_chains = {
  "braking-force",
  "research-speed",
  "worker-robots-storage",
  "inserter-capacity-bonus",
  "weapon-shooting-speed",
  "laser-shooting-speed"
}

-- Classic inherits only the native effect families named here. This is a
-- declaration boundary, not a generic ownership or effect-discovery pass.
M.base_chain_effect_types = {
  ["braking-force"] = { ["train-braking-force-bonus"] = true },
  ["research-speed"] = { ["laboratory-speed"] = true },
  ["worker-robots-storage"] = { ["worker-robot-storage"] = true },
  ["inserter-capacity-bonus"] = {
    ["inserter-stack-size-bonus"] = true,
    ["bulk-inserter-capacity-bonus"] = true,
    ["stack-inserter-capacity-bonus"] = true
  },
  ["weapon-shooting-speed"] = { ["gun-speed"] = true },
  ["laser-shooting-speed"] = { ["gun-speed"] = true }
}

return M
