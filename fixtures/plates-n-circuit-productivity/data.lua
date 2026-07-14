data:extend({
  {
    name = "basic-plate-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/advanced-material-processing.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1}
      },
      count_formula = "2500+2500*(L-1)",
      time = 30
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "copper-plate", change = 0.1},
      {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}
    },
    prerequisites = {"advanced-material-processing"}
  },
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
      {type = "change-recipe-productivity", recipe = "electronic-circuit", change = 0.1}
    },
    prerequisites = {"automation-2"}
  },
  {
    name = "advanced-circuit-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/advanced-circuit.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"science-pack-1", 1},
        {"science-pack-2", 1},
        {"science-pack-3", 1}
      },
      count_formula = "1000+1000*(L-1)",
      time = 60
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "advanced-circuit", change = 0.1}
    },
    prerequisites = {"science-pack-3"}
  }
})
