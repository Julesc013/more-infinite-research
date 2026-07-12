data:extend({
  {
    type = "technology",
    name = "laboratory-productivity-4",
    icon_size = 256,
    icon = "__base__/graphics/technology/research-speed.png",
    effects = {
      { type = "laboratory-productivity", modifier = 0.10 }
    },
    prerequisites = {"research-speed-6"},
    unit = {
      count_formula = "2500*(L-3)",
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1},
        {"science-pack-3", 1},
        {"production-science-pack", 1},
        {"high-tech-science-pack", 1},
        {"space-science-pack", 1}
      },
      time = 60
    },
    upgrade = true,
    max_level = "infinite",
    order = "c-k-f-f"
  }
})
