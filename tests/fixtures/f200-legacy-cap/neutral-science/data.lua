assert(mods.base == "2.1.23" and mods["more-infinite-research"] == nil,
  "native science control requires exact2.1.23 without MIR")
for _, name in ipairs({"space-age", "elevated-rails", "quality", "recycler"}) do
  assert(mods[name] == nil, "native science control requires Base only")
end
local ingredients = {}
for _, name in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack"}) do
  assert(data.raw.item[name] and data.raw.item[name].type == "item" and not (data.raw.tool and data.raw.tool[name]),
    "native science control item type differs: " .. name)
  ingredients[#ingredients + 1] = {name, 1}
end
data:extend({{
  type = "technology", name = "mir-fixture-native-science-consumption",
  icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
  level = 1, max_level = "infinite", upgrade = true, prerequisites = {}, effects = {},
  unit = {count_formula = "1", time = 1, ingredients = ingredients},
}})
