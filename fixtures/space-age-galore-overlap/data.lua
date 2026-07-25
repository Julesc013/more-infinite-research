data:extend({{
  type = "recipe",
  name = "vgal-coal-crushing",
  icon = "__base__/graphics/icons/coal.png",
  icon_size = 64,
  categories = {"crushing"},
  enabled = true,
  energy_required = 1,
  ingredients = {{type = "item", name = "coal", amount = 5}},
  results = {
    {type = "item", name = "coal", amount = 1, independent_probability = 0.10, ignored_by_productivity = 1},
    {type = "item", name = "carbon", amount = 1, independent_probability = 0.25},
    {type = "item", name = "sulfur", amount = 1, independent_probability = 0.50}
  },
  allow_productivity = true
}})
