data:extend({
  {
    type = "recipe",
    name = "mir-upgrade-reset-sentinel-recipe",
    enabled = false,
    energy_required = 0.5,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = "iron-gear-wheel", amount = 1}}
  },
  {
    type = "technology",
    name = "mir-upgrade-reset-sentinel-technology",
    icon = "__base__/graphics/technology/automation.png",
    icon_size = 256,
    prerequisites = {"automation"},
    effects = {
      {type = "unlock-recipe", recipe = "mir-upgrade-reset-sentinel-recipe"},
      {type = "give-item", item = "iron-plate", count = 1}
    },
    unit = {
      count = 1,
      ingredients = {{"automation-science-pack", 1}},
      time = 1
    }
  }
})
