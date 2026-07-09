local function icon()
  return "__base__/graphics/icons/iron-chest.png"
end

local function container_entity(name)
  local base = data.raw.container and data.raw.container["iron-chest"]
  if not base then return nil end
  local entity = table.deepcopy(base)
  entity.name = name
  entity.minable = {mining_time = 0.1, result = name}
  return entity
end

local function item(name, place_result)
  return {
    type = "item",
    name = name,
    icon = icon(),
    icon_size = 64,
    subgroup = "storage",
    order = "mir-negative-" .. name,
    place_result = place_result,
    stack_size = 50
  }
end

local function simple_item(name)
  return {
    type = "item",
    name = name,
    icon = icon(),
    icon_size = 64,
    subgroup = "intermediate-product",
    order = "mir-negative-" .. name,
    stack_size = 100
  }
end

local function recipe(name, ingredients, results, extra)
  local prototype = {
    type = "recipe",
    name = name,
    icon = icon(),
    icon_size = 64,
    categories = {"crafting"},
    enabled = true,
    energy_required = 1,
    ingredients = ingredients,
    results = results,
    allow_productivity = true
  }
  for key, value in pairs(extra or {}) do
    prototype[key] = value
  end
  return prototype
end

local prototypes = {
  simple_item("mir-loop-token"),
  simple_item("mir-loop-waste"),
  simple_item("mir-loop-output"),
  simple_item("mir-empty-barrel"),
  simple_item("mir-zero-cap-output"),
  item("mir-loader-like-container", "mir-loader-like-container"),
  item("mir-drill-like-container", "mir-drill-like-container"),
  recipe(
    "mir-self-loop-filter-cleaning",
    {{type = "item", name = "mir-loop-token", amount = 1}},
    {{type = "item", name = "mir-loop-token", amount = 1}}
  ),
  recipe(
    "mir-barrel-return-loop",
    {{type = "item", name = "mir-empty-barrel", amount = 1}},
    {
      {type = "item", name = "mir-empty-barrel", amount = 1},
      {type = "item", name = "mir-loop-output", amount = 1}
    }
  ),
  recipe(
    "mir-voiding-sink",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "mir-loop-waste", amount = 1}}
  ),
  recipe(
    "mir-matter-transmutation",
    {{type = "item", name = "copper-plate", amount = 1}},
    {{type = "item", name = "mir-loop-output", amount = 1}}
  ),
  recipe(
    "mir-zero-cap-productivity",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "mir-zero-cap-output", amount = 1}},
    {maximum_productivity = 0}
  ),
  recipe(
    "mir-hidden-internal-recipe",
    {{type = "item", name = "copper-plate", amount = 1}},
    {{type = "item", name = "mir-loop-output", amount = 1}},
    {hidden = true}
  ),
  recipe(
    "mir-loader-like-container",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "mir-loader-like-container", amount = 1}}
  ),
  recipe(
    "mir-drill-like-container",
    {{type = "item", name = "iron-plate", amount = 1}},
    {{type = "item", name = "mir-drill-like-container", amount = 1}}
  )
}

local loader_like = container_entity("mir-loader-like-container")
if loader_like then table.insert(prototypes, loader_like) end

local drill_like = container_entity("mir-drill-like-container")
if drill_like then table.insert(prototypes, drill_like) end

data:extend(prototypes)
