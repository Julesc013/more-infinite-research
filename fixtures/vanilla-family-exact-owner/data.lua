data:extend({
  {
    type = "recipe",
    name = "mir-fixture-exact-owned-rocket-fuel",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "solid-fuel", amount = 10}
    },
    results = {
      {type = "item", name = "rocket-fuel", amount = 1}
    },
    main_product = "rocket-fuel",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "technology",
    name = "mir-fixture-exact-owned-rocket-fuel-productivity",
    icon = "__base__/graphics/technology/rocket-fuel.png",
    icon_size = 256,
    effects = {
      {
        type = "change-recipe-productivity",
        recipe = "mir-fixture-exact-owned-rocket-fuel",
        change = 0.1
      }
    },
    unit = {
      count_formula = "1000 * 2^(L-1)",
      ingredients = {
        {"automation-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true
  },
  {
    type = "recipe",
    name = "mir-fixture-exact-owned-steel-plate",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "iron-plate", amount = 5}
    },
    results = {
      {type = "item", name = "steel-plate", amount = 1}
    },
    main_product = "steel-plate",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "technology",
    name = "mir-fixture-exact-owned-steel-productivity",
    icon = "__base__/graphics/technology/steel-processing.png",
    icon_size = 256,
    effects = {
      {
        type = "change-recipe-productivity",
        recipe = "mir-fixture-exact-owned-steel-plate",
        change = 0.1
      }
    },
    unit = {
      count_formula = "1000 * 2^(L-1)",
      ingredients = {
        {"automation-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true
  }
})
