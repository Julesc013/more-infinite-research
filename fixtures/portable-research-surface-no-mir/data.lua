local technologies = {
  {
    type = "technology", name = "portable-surface-infinite", icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64,
    max_level = "infinite", unit = {count_formula = "L", time = 1, ingredients = {{"automation-science-pack", 1}}}
  }
}
for index = 1, 25 do
  technologies[#technologies + 1] = {
    type = "technology", name = string.format("portable-surface-item-%02d", index), icon = "__base__/graphics/icons/iron-plate.png", icon_size = 64,
    unit = {count = 1, time = 1, ingredients = {{"automation-science-pack", 1}}}
  }
end
data:extend(technologies)
