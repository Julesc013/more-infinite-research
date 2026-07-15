require("config")

local mir_hard_limits = {
  ["inserter-capacity"] = 5,
  ["gun-turret-damage"] = 5,
  ["bullet-shooting-speed"] = 5,
  ["bullet-damage"] = 5,
  ["toolbelt"] = 3
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
if mir_family_enabled("gun-turret-damage", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-gun-turret-damage-1",
    icon = "__base__/graphics/technology/gun-turret-damage.png",
    effects = {
      {
        type = "turret-attack",
        turret_id = "gun-turret",
        modifier = 0.2
      }
    },
    prerequisites = {"gun-turret-damage-6"},
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
    order = "z[mir]-gun-turret-damage-01"
  })
end
if mir_family_enabled("gun-turret-damage", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-gun-turret-damage-2",
    icon = "__base__/graphics/technology/gun-turret-damage.png",
    effects = {
      {
        type = "turret-attack",
        turret_id = "gun-turret",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-gun-turret-damage-1"},
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
    order = "z[mir]-gun-turret-damage-02"
  })
end
if mir_family_enabled("gun-turret-damage", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-gun-turret-damage-3",
    icon = "__base__/graphics/technology/gun-turret-damage.png",
    effects = {
      {
        type = "turret-attack",
        turret_id = "gun-turret",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-gun-turret-damage-2"},
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
    order = "z[mir]-gun-turret-damage-03"
  })
end
if mir_family_enabled("gun-turret-damage", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-gun-turret-damage-4",
    icon = "__base__/graphics/technology/gun-turret-damage.png",
    effects = {
      {
        type = "turret-attack",
        turret_id = "gun-turret",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-gun-turret-damage-3"},
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
    order = "z[mir]-gun-turret-damage-04"
  })
end
if mir_family_enabled("gun-turret-damage", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-gun-turret-damage-5",
    icon = "__base__/graphics/technology/gun-turret-damage.png",
    effects = {
      {
        type = "turret-attack",
        turret_id = "gun-turret",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-gun-turret-damage-4"},
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
    order = "z[mir]-gun-turret-damage-05"
  })
end
if mir_family_enabled("bullet-shooting-speed", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-shooting-speed-1",
    icon = "__base__/graphics/technology/bullet-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        modifier = 0.15
      }
    },
    prerequisites = {"bullet-speed-6"},
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
    order = "z[mir]-bullet-shooting-speed-01"
  })
end
if mir_family_enabled("bullet-shooting-speed", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-shooting-speed-2",
    icon = "__base__/graphics/technology/bullet-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-bullet-shooting-speed-1"},
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
    order = "z[mir]-bullet-shooting-speed-02"
  })
end
if mir_family_enabled("bullet-shooting-speed", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-shooting-speed-3",
    icon = "__base__/graphics/technology/bullet-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-bullet-shooting-speed-2"},
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
    order = "z[mir]-bullet-shooting-speed-03"
  })
end
if mir_family_enabled("bullet-shooting-speed", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-shooting-speed-4",
    icon = "__base__/graphics/technology/bullet-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-bullet-shooting-speed-3"},
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
    order = "z[mir]-bullet-shooting-speed-04"
  })
end
if mir_family_enabled("bullet-shooting-speed", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-shooting-speed-5",
    icon = "__base__/graphics/technology/bullet-speed.png",
    effects = {
      {
        type = "gun-speed",
        ammo_category = "bullet",
        modifier = 0.15
      }
    },
    prerequisites = {"mir-bullet-shooting-speed-4"},
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
    order = "z[mir]-bullet-shooting-speed-05"
  })
end
if mir_family_enabled("bullet-damage", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-damage-1",
    icon = "__base__/graphics/technology/bullet-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "bullet",
        modifier = 0.2
      }
    },
    prerequisites = {"bullet-damage-6"},
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
    order = "z[mir]-bullet-damage-01"
  })
end
if mir_family_enabled("bullet-damage", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-damage-2",
    icon = "__base__/graphics/technology/bullet-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "bullet",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-bullet-damage-1"},
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
    order = "z[mir]-bullet-damage-02"
  })
end
if mir_family_enabled("bullet-damage", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-damage-3",
    icon = "__base__/graphics/technology/bullet-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "bullet",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-bullet-damage-2"},
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
    order = "z[mir]-bullet-damage-03"
  })
end
if mir_family_enabled("bullet-damage", 4) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-damage-4",
    icon = "__base__/graphics/technology/bullet-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "bullet",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-bullet-damage-3"},
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
    order = "z[mir]-bullet-damage-04"
  })
end
if mir_family_enabled("bullet-damage", 5) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-bullet-damage-5",
    icon = "__base__/graphics/technology/bullet-damage.png",
    effects = {
      {
        type = "ammo-damage",
        ammo_category = "bullet",
        modifier = 0.2
      }
    },
    prerequisites = {"mir-bullet-damage-4"},
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
    order = "z[mir]-bullet-damage-05"
  })
end
if mir_family_enabled("toolbelt", 1) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-toolbelt-1",
    icon = "__base__/graphics/technology/toolbelt.png",
    effects = {
      {
        type = "num-quick-bars",
        modifier = 1
      }
    },
    prerequisites = {"toolbelt"},
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
    order = "z[mir]-toolbelt-01"
  })
end
if mir_family_enabled("toolbelt", 2) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-toolbelt-2",
    icon = "__base__/graphics/technology/toolbelt.png",
    effects = {
      {
        type = "num-quick-bars",
        modifier = 1
      }
    },
    prerequisites = {"mir-toolbelt-1"},
    unit = {
      count = 900,
      ingredients = {
      {"science-pack-1", 1},
      {"science-pack-2", 1},
      {"science-pack-3", 1},
      {"alien-science-pack", 1}
      },
      time = 45
    },
    upgrade = true,
    order = "z[mir]-toolbelt-02"
  })
end
if mir_family_enabled("toolbelt", 3) then
  table.insert(mir_technologies, {
    type = "technology",
    name = "mir-toolbelt-3",
    icon = "__base__/graphics/technology/toolbelt.png",
    effects = {
      {
        type = "num-quick-bars",
        modifier = 1
      }
    },
    prerequisites = {"mir-toolbelt-2"},
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
    order = "z[mir]-toolbelt-03"
  })
end

data:extend(mir_technologies)
