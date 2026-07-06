local pack = {
  type = "tool",
  name = "mir-fixture-science-pack",
  icon = "__base__/graphics/icons/automation-science-pack.png",
  icon_size = 64,
  subgroup = "science-pack",
  order = "z[mir-fixture-science-pack]",
  stack_size = 200,
  durability = 1,
  durability_description_key = "description.science-pack-remaining-amount-key",
  factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key",
  durability_description_value = "description.science-pack-remaining-amount-value"
}

local recipe = {
  type = "recipe",
  name = "mir-fixture-science-pack",
  enabled = false,
  ingredients = {
    {type = "item", name = "automation-science-pack", amount = 1}
  },
  results = {
    {type = "item", name = "mir-fixture-science-pack", amount = 1}
  }
}

local tech = {
  type = "technology",
  name = "mir-fixture-science-pack",
  icon = "__base__/graphics/technology/automation-science-pack.png",
  icon_size = 256,
  effects = {
    {type = "unlock-recipe", recipe = "mir-fixture-science-pack"}
  },
  unit = {
    count = 10,
    ingredients = {{"automation-science-pack", 1}},
    time = 10
  }
}

data:extend({pack, recipe, tech})

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, "mir-fixture-science-pack")
end
