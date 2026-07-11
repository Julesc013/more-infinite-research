local prototypes = {}
local previous = "iron-plate"

for index = 1, 1000 do
  local item_name = string.format("mir-fixture-synthetic-item-%04d", index)
  table.insert(prototypes, {
    type = "item",
    name = item_name,
    icon = "__base__/graphics/icons/iron-plate.png",
    icon_size = 64,
    stack_size = 1,
    hidden = true
  })
  table.insert(prototypes, {
    type = "recipe",
    name = string.format("mir-fixture-synthetic-recipe-%04d", index),
    enabled = true,
    hidden = true,
    allow_productivity = true,
    ingredients = {{type = "item", name = previous, amount = 1}},
    results = {{type = "item", name = item_name, amount = 1}}
  })
  previous = item_name
end

data:extend(prototypes)
