local function item(name)
  return {
    type = "item",
    name = name,
    icon = "__base__/graphics/icons/electric-mining-drill.png",
    icon_size = 64,
    subgroup = "extraction-machine",
    order = "z[" .. name .. "]",
    stack_size = 50
  }
end

local function recipe(name, ingredient)
  return {
    type = "recipe",
    name = name,
    enabled = true,
    ingredients = {
      {type = "item", name = ingredient or "electric-mining-drill", amount = 1},
      {type = "item", name = "steel-plate", amount = 1}
    },
    results = {
      {type = "item", name = name, amount = 1}
    }
  }
end

data:extend({
  item("omega-drill"),
  item("omega-tau"),
  recipe("omega-drill", "electric-mining-drill"),
  recipe("omega-tau", "omega-drill")
})
