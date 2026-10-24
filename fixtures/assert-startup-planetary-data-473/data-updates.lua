-- Representative reporter shape: a lab input without a same-name recipe and
-- several typed producers. The first producer cannot bootstrap its own pack.
local pack = table.deepcopy((data.raw.item or {})["automation-science-pack"]
  or (data.raw.tool or {})["automation-science-pack"])
pack.name = "planetary-data"
assert(not (data.raw[pack.type] or {})[pack.name], "Use the real planetary-data profile instead of replacing its prototype")
data:extend({pack})
for _, lab in pairs(data.raw.lab) do lab.inputs[#lab.inputs + 1] = pack.name end
data:extend({
  {type = "recipe", name = "a-mir473-circular-planetary-data", enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = pack.name, amount = 1}}},
  {type = "recipe", name = "z-mir473-seeded-planetary-data", enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = pack.name, amount = 1}}},
  {type = "technology", name = "mir473-circular-planetary-owner",
    icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
    unit = {count = 1, time = 1, ingredients = {{pack.name, 1}}},
    effects = {{type = "unlock-recipe", recipe = "a-mir473-circular-planetary-data"}}},
  {type = "technology", name = "mir473-seeded-planetary-owner",
    icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
    effects = {{type = "unlock-recipe", recipe = "z-mir473-seeded-planetary-data"}}}
})
