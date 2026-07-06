local icon = "__base__/graphics/icons/transport-belt.png"

local function loader_item(name, order)
  return {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = "belt",
    order = "mir-loader-" .. order,
    stack_size = 50
  }
end

local function loader_recipe(name, belt, order)
  return {
    type = "recipe",
    name = name,
    categories = {"crafting"},
    enabled = true,
    energy_required = 1,
    ingredients = {
      {type = "item", name = belt, amount = 1},
      {type = "item", name = "iron-gear-wheel", amount = 2}
    },
    results = {
      {type = "item", name = name, amount = 1}
    },
    allow_productivity = true,
    order = "mir-loader-" .. order
  }
end

data:extend({
  loader_item("aai-loader", "a"),
  loader_item("aai-fast-loader", "b"),
  loader_item("aai-express-loader", "c"),
  loader_item("aai-turbo-loader", "d"),
  loader_recipe("aai-loader", "transport-belt", "a"),
  loader_recipe("aai-fast-loader", "fast-transport-belt", "b"),
  loader_recipe("aai-express-loader", "express-transport-belt", "c"),
  loader_recipe("aai-turbo-loader", "express-transport-belt", "d")
})
