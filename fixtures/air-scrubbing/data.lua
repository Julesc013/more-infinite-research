data:extend({
  {
    type = "recipe-category",
    name = "atmospheric-filtration"
  },
  {
    type = "item",
    name = "atan-pollution-filter",
    icon = "__base__/graphics/icons/steel-plate.png",
    icon_size = 64,
    stack_size = 100
  },
  {
    type = "item",
    name = "atan-used-pollution-filter",
    icon = "__base__/graphics/icons/stone.png",
    icon_size = 64,
    stack_size = 100
  },
  {
    type = "recipe",
    name = "atan-pollution-filter",
    enabled = false,
    ingredients = {
      {type = "item", name = "coal", amount = 2},
      {type = "item", name = "steel-plate", amount = 1}
    },
    results = {
      {type = "item", name = "atan-pollution-filter", amount = 1}
    }
  },
  {
    type = "recipe",
    name = "atan-pollution-filter-cleaning",
    category = "chemistry",
    enabled = false,
    ingredients = {
      {type = "item", name = "atan-used-pollution-filter", amount = 10},
      {type = "fluid", name = "water", amount = 100}
    },
    results = {
      {type = "item", name = "atan-pollution-filter", amount = 8}
    }
  },
  {
    type = "recipe",
    name = "atan-pollution-scrubbing",
    category = "atmospheric-filtration",
    enabled = false,
    allow_productivity = false,
    ingredients = {
      {type = "item", name = "atan-pollution-filter", amount = 1}
    },
    results = {
      {type = "item", name = "atan-used-pollution-filter", amount = 1}
    }
  },
  {
    type = "technology",
    name = "atan-pollution-scrubbing",
    icon = "__base__/graphics/technology/effectivity-module.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "atan-pollution-filter"},
      {type = "unlock-recipe", recipe = "atan-pollution-filter-cleaning"},
      {type = "unlock-recipe", recipe = "atan-pollution-scrubbing"}
    },
    prerequisites = {"chemical-science-pack"},
    unit = {
      count = 250,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    }
  }
})

if mods["space-age"] then
  data:extend({
    {
      type = "item",
      name = "atan-spore-filter",
      icon = "__base__/graphics/icons/steel-plate.png",
      icon_size = 64,
      stack_size = 100
    },
    {
      type = "item",
      name = "atan-used-spore-filter",
      icon = "__base__/graphics/icons/stone.png",
      icon_size = 64,
      stack_size = 100
    },
    {
      type = "recipe",
      name = "atan-spore-filter",
      enabled = false,
      ingredients = {
        {type = "item", name = "carbon", amount = 2},
        {type = "item", name = "steel-plate", amount = 1}
      },
      results = {
        {type = "item", name = "atan-spore-filter", amount = 1}
      }
    },
    {
      type = "recipe",
      name = "atan-spore-filter-cleaning",
      category = "chemistry",
      enabled = false,
      ingredients = {
        {type = "item", name = "atan-used-spore-filter", amount = 10},
        {type = "fluid", name = "water", amount = 100}
      },
      results = {
        {type = "item", name = "atan-spore-filter", amount = 8}
      }
    },
    {
      type = "recipe",
      name = "atan-spore-scrubbing",
      category = "atmospheric-filtration",
      enabled = false,
      allow_productivity = false,
      ingredients = {
        {type = "item", name = "atan-spore-filter", amount = 1}
      },
      results = {
        {type = "item", name = "atan-used-spore-filter", amount = 1}
      }
    },
    {
      type = "technology",
      name = "atan-spore-scrubbing",
      icon = "__base__/graphics/technology/effectivity-module.png",
      icon_size = 256,
      effects = {
        {type = "unlock-recipe", recipe = "atan-spore-filter"},
        {type = "unlock-recipe", recipe = "atan-spore-filter-cleaning"},
        {type = "unlock-recipe", recipe = "atan-spore-scrubbing"}
      },
      prerequisites = {"atan-pollution-scrubbing"},
      unit = {
        count = 250,
        ingredients = {
          {"automation-science-pack", 1},
          {"logistic-science-pack", 1},
          {"chemical-science-pack", 1},
          {"agricultural-science-pack", 1}
        },
        time = 30
      }
    }
  })
end
