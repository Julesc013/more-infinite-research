local function recipe(name)
  return {
    type = "recipe",
    name = name,
    categories = {"crafting"},
    enabled = false,
    ingredients = {{type = "item", name = "iron-ore", amount = 1}},
    results = {{type = "item", name = "iron-plate", amount = 1}}
  }
end

data:extend({
  recipe("casting-valid-a"),
  recipe("casting-gear"),
  recipe("casting-valid-b"),
  {
    type = "technology",
    name = "casting-mk02",
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    prerequisites = {"automation"},
    effects = {
      {type = "unlock-recipe", recipe = "casting-valid-a"},
      {type = "unlock-recipe", recipe = "casting-gear"},
      {type = "unlock-recipe", recipe = "casting-valid-b"}
    },
    unit = {
      count = 10,
      time = 5,
      ingredients = {{"automation-science-pack", 1}}
    }
  }
})