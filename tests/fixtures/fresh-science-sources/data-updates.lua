-- Published 4.7.3's representative unfamiliar lab input: clone the existing
-- automation tool rather than manufacturing a distinct prototype shape.
local pack = table.deepcopy((data.raw.item or {})["automation-science-pack"]
  or (data.raw.tool or {})["automation-science-pack"])
pack.name = "planetary-data"
assert(not (data.raw[pack.type] or {})[pack.name], "fresh science fixture already has planetary-data")
data:extend({pack})

for _, lab in pairs(data.raw.lab) do lab.inputs[#lab.inputs + 1] = pack.name end

-- Keep these historical fixture symbols local to test data. The a-route is
-- circular; the z-route is the sole independently seeded route.
data:extend({
  {type = "recipe", name = "a-mir473-circular-planetary-data", enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = pack.name, amount = 1}}},
  {type = "recipe", name = "z-mir473-seeded-planetary-data", enabled = false,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = pack.name, amount = 1}}},
  {type = "technology", name = "mir473-circular-planetary-owner",
    icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
    unit = {count = 1, time = 1, ingredients = {{pack.name, 1}}}, prerequisites = {},
    effects = {{type = "unlock-recipe", recipe = "a-mir473-circular-planetary-data"}}},
  {type = "technology", name = "mir473-seeded-planetary-owner",
    icon = "__base__/graphics/technology/automation-1.png", icon_size = 256,
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1}, prerequisites = {},
    effects = {{type = "unlock-recipe", recipe = "z-mir473-seeded-planetary-data"}}}
})
