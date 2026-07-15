local icon = "__base__/graphics/icons/plastic-bar.png"

data:extend({
  {
    type = "item",
    name = "atan-pollution-filter",
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-air-a",
    stack_size = 100
  },
  {
    type = "item",
    name = "atan-spore-filter",
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-air-b",
    stack_size = 100
  },
  {
    type = "item",
    name = "atan-dirty-pollution-filter",
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-air-c",
    stack_size = 100
  },
  {
    type = "item",
    name = "atan-dirty-spore-filter",
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-air-d",
    stack_size = 100
  },
  {
    type = "item",
    name = "atan-filter-resin",
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-air-e",
    stack_size = 100
  },
  {
    type = "recipe",
    name = "atan-pollution-filter",
    categories = {"crafting"},
    enabled = false,
    energy_required = 4,
    ingredients = {
      {type = "item", name = "coal", amount = 1},
      {type = "item", name = "plastic-bar", amount = 1}
    },
    results = {{type = "item", name = "atan-pollution-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-spore-filter",
    categories = {"crafting"},
    enabled = false,
    energy_required = 4,
    ingredients = {
      {type = "item", name = "coal", amount = 1},
      {type = "item", name = "plastic-bar", amount = 1}
    },
    results = {{type = "item", name = "atan-spore-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-pollution-scrubbing",
    categories = {"crafting"},
    enabled = false,
    energy_required = 10,
    ingredients = {{type = "item", name = "atan-pollution-filter", amount = 1}},
    results = {{type = "item", name = "atan-dirty-pollution-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-spore-scrubbing",
    categories = {"crafting"},
    enabled = false,
    energy_required = 10,
    ingredients = {{type = "item", name = "atan-spore-filter", amount = 1}},
    results = {{type = "item", name = "atan-dirty-spore-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-pollution-filter-cleaning",
    categories = {"crafting"},
    enabled = false,
    energy_required = 6,
    ingredients = {
      {type = "item", name = "atan-dirty-pollution-filter", amount = 1},
      {type = "item", name = "coal", amount = 1}
    },
    results = {{type = "item", name = "atan-pollution-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-spore-filter-cleaning",
    categories = {"crafting"},
    enabled = false,
    energy_required = 6,
    ingredients = {
      {type = "item", name = "atan-dirty-spore-filter", amount = 1},
      {type = "item", name = "coal", amount = 1}
    },
    results = {{type = "item", name = "atan-spore-filter", amount = 1}},
    allow_productivity = true
  },
  {
    type = "recipe",
    name = "atan-filter-resin",
    categories = {"crafting"},
    enabled = false,
    energy_required = 2,
    ingredients = {{type = "item", name = "coal", amount = 1}},
    results = {{type = "item", name = "atan-filter-resin", amount = 1}},
    allow_productivity = true
  },
  {
    type = "technology",
    name = "atan-pollution-scrubbing",
    icon = "__base__/graphics/technology/oil-processing.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "atan-pollution-filter"},
      {type = "unlock-recipe", recipe = "atan-pollution-scrubbing"},
      {type = "unlock-recipe", recipe = "atan-pollution-filter-cleaning"},
      {type = "unlock-recipe", recipe = "atan-filter-resin"}
    },
    prerequisites = {"chemical-science-pack"},
    unit = {
      count = 100,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    }
  },
  {
    type = "technology",
    name = "atan-spore-scrubbing",
    icon = "__base__/graphics/technology/oil-processing.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "atan-spore-filter"},
      {type = "unlock-recipe", recipe = "atan-spore-scrubbing"},
      {type = "unlock-recipe", recipe = "atan-spore-filter-cleaning"}
    },
    prerequisites = {"atan-pollution-scrubbing"},
    unit = {
      count = 100,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    }
  }
})
