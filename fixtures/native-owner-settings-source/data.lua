-- The owner patch is intentionally applied during data-updates so every
-- data-final-fixes planner observes it regardless of sibling mod order.

data:extend({
  {
    type = "item",
    name = "mir-reset-safety-token",
    icon = "__base__/graphics/icons/iron-plate.png",
    icon_size = 64,
    stack_size = 100
  },
  {
    type = "recipe",
    name = "mir-reset-safety-recipe",
    enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = "mir-reset-safety-token", amount = 1}}
  },
  {
    type = "technology",
    name = "mir-external-give-item-technology",
    icon = "__base__/graphics/technology/logistics.png",
    icon_size = 256,
    effects = {
      {type = "give-item", item = "mir-reset-safety-token", count = 1},
      {type = "unlock-recipe", recipe = "mir-reset-safety-recipe"}
    },
    unit = {
      count = 1,
      ingredients = {{"automation-science-pack", 1}},
      time = 1
    }
  }
})
