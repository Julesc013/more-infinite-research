data:extend({
  {
    name = "electric-circuit-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/electronics.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1}
      },
      count_formula = "1000+1000*(L-1)",
      time = 30
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "electronic-circuit", change = 0.05}
    },
    prerequisites = {"automation-2"}
  }
})
