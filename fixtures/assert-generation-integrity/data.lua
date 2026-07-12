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

table.insert(prototypes, {
  type = "recipe",
  name = "mir-fixture-default-productivity-policy",
  enabled = true,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}},
  results = {{type = "item", name = "iron-gear-wheel", amount = 1}}
})
table.insert(prototypes, {
  type = "recipe",
  name = "mir-fixture-complete-product-shape",
  enabled = true,
  allow_productivity = true,
  ingredients = {{type = "item", name = "iron-plate", amount = 1}},
  results = {{
    type = "item",
    name = "copper-plate",
    amount = 1,
    independent_probability = 0.5,
    extra_count_fraction = 0.25,
    percent_spoiled = 0.1,
    always_fresh = true,
    reset_freshness_on_craft = true,
    quality_min = "normal",
    quality_max = "normal",
    quality_change = 0,
    affected_by_quality = false
  }}
})

data:extend(prototypes)
