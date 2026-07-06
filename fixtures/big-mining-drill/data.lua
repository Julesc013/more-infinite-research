data:extend({
  {
    type = "item",
    name = "big-mining-drill",
    icon = "__base__/graphics/icons/electric-mining-drill.png",
    icon_size = 64,
    subgroup = "extraction-machine",
    order = "mir-big-mining-drill",
    stack_size = 50
  },
  {
    type = "recipe",
    name = "big-mining-drill",
    categories = {"crafting"},
    enabled = true,
    energy_required = 5,
    ingredients = {
      {type = "item", name = "electric-mining-drill", amount = 1},
      {type = "item", name = "steel-plate", amount = 10}
    },
    results = {
      {type = "item", name = "big-mining-drill", amount = 1}
    },
    allow_productivity = true
  }
})
