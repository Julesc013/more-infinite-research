data:extend({
  {
    type = "technology",
    name = "weapon-shooting-speed-7",
    icon = "__base__/graphics/technology/weapon-shooting-speed-3.png",
    icon_size = 256,
    effects = {
      {type = "gun-speed", ammo_category = "cannon-shell", modifier = 0.25},
      {type = "gun-speed", ammo_category = "rocket", modifier = 0.25}
    },
    prerequisites = {"rocketry", "tank"},
    unit = {
      count_formula = "1000*(L-6)",
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"military-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    order = "e-a-b-z"
  }
})
