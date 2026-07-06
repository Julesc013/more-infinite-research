local science_icon = "__base__/graphics/icons/utility-science-pack.png"

data:extend({
  {
    type = "tool",
    name = "nuclear-science-pack",
    icon = science_icon,
    icon_size = 64,
    subgroup = "science-pack",
    order = "mir-nuclear-science-pack",
    stack_size = 200,
    durability = 1,
    durability_description_key = "description.science-pack-remaining-amount-key",
    factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key",
    durability_description_value = "description.science-pack-remaining-amount-value"
  },
  {
    type = "item",
    name = "atan-atom-forge",
    icon = "__base__/graphics/icons/assembling-machine-3.png",
    icon_size = 64,
    subgroup = "production-machine",
    order = "mir-atom-forge",
    stack_size = 20
  },
  {
    type = "recipe",
    name = "atan-atom-forge",
    categories = {"crafting"},
    enabled = false,
    energy_required = 10,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 10}
    },
    results = {
      {type = "item", name = "atan-atom-forge", amount = 1}
    },
    allow_productivity = false
  },
  {
    type = "recipe",
    name = "nuclear-science-pack",
    icon = science_icon,
    icon_size = 64,
    categories = {"crafting"},
    enabled = false,
    energy_required = 12,
    ingredients = {
      {type = "item", name = "uranium-235", amount = 1},
      {type = "item", name = "barrel", amount = 1}
    },
    results = {
      {type = "item", name = "nuclear-science-pack", amount = 2},
      {type = "item", name = "barrel", amount = 1, ignored_by_productivity = 1}
    },
    allow_productivity = true
  },
  {
    type = "technology",
    name = "atan-nuclear-science",
    icon = "__base__/graphics/technology/nuclear-power.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "atan-atom-forge"},
      {type = "unlock-recipe", recipe = "nuclear-science-pack"}
    },
    prerequisites = {"uranium-processing"},
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

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, "nuclear-science-pack")
end
