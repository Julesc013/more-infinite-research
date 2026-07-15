local recipe_names = {
  "item-microculture-vat-incineration",
  "example-culture-incinerate",
  "example-incineration",
  "microculture-vat-breeding",
  "microculture-cultivation",
  "mir-fixture-normal-crafting"
}

local recipes = {}
for _, name in ipairs(recipe_names) do
  table.insert(recipes, {
    type = "recipe",
    name = name,
    categories = {"crafting"},
    enabled = true,
    hidden = false,
    allow_productivity = true,
    ingredients = {
      {type = "item", name = "iron-ore", amount = 1}
    },
    results = {
      {type = "item", name = "stone", amount = 1}
    }
  })
end

data:extend(recipes)
