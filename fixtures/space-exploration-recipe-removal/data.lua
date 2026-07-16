data:extend({
  {
    type = "recipe",
    name = "kr-copper-cable-from-copper-ore",
    category = "crafting",
    enabled = true,
    hidden = false,
    allow_productivity = true,
    ingredients = {
      {type = "item", name = "copper-ore", amount = 1}
    },
    results = {
      {type = "item", name = "copper-cable", amount = 2}
    }
  },
  {
    type = "technology",
    name = "mir-fixture-external-dangling-unlock",
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "copper-cable"},
      {type = "unlock-recipe", recipe = "kr-copper-cable-from-copper-ore"}
    },
    unit = {
      count = 1,
      ingredients = {{"automation-science-pack", 1}},
      time = 1
    }
  }
})
