require("config")

local mir_hard_limits = {
  ["inserter-capacity"] = 5,
  ["rocket-shooting-speed"] = 5,
  ["rocket-damage"] = 5
}
local function mir_family_enabled(id, level)
  local configured = mir_config[id]
  local hard_limit = mir_hard_limits[id]
  return configured and configured.enabled == true and type(configured.levels) == "number" and configured.levels >= level and level <= hard_limit
end
local mir_technologies = {}

if mir_family_enabled("inserter-capacity", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-inserter-capacity-1",
    icon = "__base__/graphics/technology/inserter-stack-size-bonus.png",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        modifier = 1
      }
    },
    prerequisites = {"inserter-stack-size-bonus-4"},
    unit = {
      count = 400,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-inserter-capacity-01"
  })
end
if mir_family_enabled("inserter-capacity", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-inserter-capacity-2",
    icon = "__base__/graphics/technology/inserter-stack-size-bonus.png",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        modifier = 1
      }
    },
    prerequisites = {"mir-inserter-capacity-1"},
    unit = {
      count = 600,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-inserter-capacity-02"
  })
end
if mir_family_enabled("inserter-capacity", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-inserter-capacity-3",
    icon = "__base__/graphics/technology/inserter-stack-size-bonus.png",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        modifier = 1
      }
    },
    prerequisites = {"mir-inserter-capacity-2"},
    unit = {
      count = 800,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-inserter-capacity-03"
  })
end
if mir_family_enabled("inserter-capacity", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-inserter-capacity-4",
    icon = "__base__/graphics/technology/inserter-stack-size-bonus.png",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        modifier = 1
      }
    },
    prerequisites = {"mir-inserter-capacity-3"},
    unit = {
      count = 1000,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-inserter-capacity-04"
  })
end
if mir_family_enabled("inserter-capacity", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-inserter-capacity-5",
    icon = "__base__/graphics/technology/inserter-stack-size-bonus.png",
    effects = {
      {
        type = "inserter-stack-size-bonus",
        modifier = 1
      }
    },
    prerequisites = {"mir-inserter-capacity-4"},
    unit = {
      count = 1200,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-inserter-capacity-05"
  })
end
if mir_family_enabled("rocket-shooting-speed", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-shooting-speed-1",
    icon = "__base__/graphics/technology/rocket-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "rocket",
        modifier = 0.15
      }
    },
    prerequisites = {"rocket-speed-5"},
    unit = {
      count = 500,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-shooting-speed-01"
  })
end
if mir_family_enabled("rocket-shooting-speed", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-shooting-speed-2",
    icon = "__base__/graphics/technology/rocket-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "rocket",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-rocket-shooting-speed-1"},
    unit = {
      count = 750,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-shooting-speed-02"
  })
end
if mir_family_enabled("rocket-shooting-speed", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-shooting-speed-3",
    icon = "__base__/graphics/technology/rocket-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "rocket",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-rocket-shooting-speed-2"},
    unit = {
      count = 1000,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-shooting-speed-03"
  })
end
if mir_family_enabled("rocket-shooting-speed", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-shooting-speed-4",
    icon = "__base__/graphics/technology/rocket-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "rocket",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-rocket-shooting-speed-3"},
    unit = {
      count = 1250,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-shooting-speed-04"
  })
end
if mir_family_enabled("rocket-shooting-speed", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-shooting-speed-5",
    icon = "__base__/graphics/technology/rocket-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "rocket",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-rocket-shooting-speed-4"},
    unit = {
      count = 1500,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-shooting-speed-05"
  })
end
if mir_family_enabled("rocket-damage", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-damage-1",
    icon = "__base__/graphics/technology/rocket-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "rocket",
        modifier = 0.2
      }
    },
    prerequisites = {"rocket-damage-5"},
    unit = {
      count = 500,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-damage-01"
  })
end
if mir_family_enabled("rocket-damage", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-damage-2",
    icon = "__base__/graphics/technology/rocket-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "rocket",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-rocket-damage-1"},
    unit = {
      count = 750,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-damage-02"
  })
end
if mir_family_enabled("rocket-damage", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-damage-3",
    icon = "__base__/graphics/technology/rocket-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "rocket",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-rocket-damage-2"},
    unit = {
      count = 1000,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-damage-03"
  })
end
if mir_family_enabled("rocket-damage", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-damage-4",
    icon = "__base__/graphics/technology/rocket-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "rocket",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-rocket-damage-3"},
    unit = {
      count = 1250,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-damage-04"
  })
end
if mir_family_enabled("rocket-damage", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-rocket-damage-5",
    icon = "__base__/graphics/technology/rocket-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "rocket",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-rocket-damage-4"},
    unit = {
      count = 1500,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    order = "z[mir]-rocket-damage-05"
  })
end

data:extend(mir_technologies)
