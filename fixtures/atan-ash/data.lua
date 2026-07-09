local icon = "__base__/graphics/icons/coal.png"

local function item(name)
  return {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-ash-" .. name,
    stack_size = 100
  }
end

local function recipe(name, results, allow_productivity)
  return {
    type = "recipe",
    name = name,
    icon = icon,
    icon_size = 64,
    categories = {"crafting"},
    enabled = false,
    energy_required = 4,
    ingredients = {{type = "item", name = "atan-ash", amount = 10}},
    results = results,
    allow_productivity = allow_productivity
  }
end

local prototypes = {}

local function add_item_if_missing(name)
  if not data.raw.item[name] then
    table.insert(prototypes, item(name))
  end
end

add_item_if_missing("atan-ash")
add_item_if_missing("nutrients")
add_item_if_missing("foundation")

table.insert(
  prototypes,
  recipe(
    "atan-ash-seperation",
    {
      {type = "item", name = "coal", amount = 1},
      {type = "item", name = "iron-ore", amount = 1, independent_probability = 0.1}
    },
    true
  )
)
table.insert(
  prototypes,
  recipe(
    "atan-landfill-from-ash",
    {{type = "item", name = "landfill", amount = 1}},
    true
  )
)
table.insert(
  prototypes,
  recipe(
    "atan-stone-brick-from-ash",
    {{type = "item", name = "stone-brick", amount = 1}},
    true
  )
)
table.insert(
  prototypes,
  recipe(
    "atan-nutrients-from-ash",
    {{type = "item", name = "nutrients", amount = 1}},
    true
  )
)
table.insert(
  prototypes,
  recipe(
    "atan-foundation-from-ash",
    {{type = "item", name = "foundation", amount = 1}},
    true
  )
)
table.insert(
  prototypes,
  {
    type = "technology",
    name = "atan-ash-processing",
    icon = "__base__/graphics/technology/coal-liquefaction.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "atan-ash-seperation"},
      {type = "unlock-recipe", recipe = "atan-landfill-from-ash"},
      {type = "unlock-recipe", recipe = "atan-stone-brick-from-ash"},
      {type = "unlock-recipe", recipe = "atan-nutrients-from-ash"},
      {type = "unlock-recipe", recipe = "atan-foundation-from-ash"}
    },
    prerequisites = {"chemical-science-pack"},
    unit = {
      count = 100,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    }
  }
)

data:extend(prototypes)
