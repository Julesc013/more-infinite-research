local icon = "__base__/graphics/icons/transport-belt.png"

local loader_names = {
  "aai-loader",
  "aai-fast-loader",
  "aai-express-loader",
  "aai-turbo-loader"
}

local function loader_item(name, order)
  return {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = "belt",
    order = "mir-loader-" .. order,
    place_result = name,
    stack_size = 50
  }
end

local function loader_entity(name)
  local base = data.raw["loader-1x1"] and data.raw["loader-1x1"]["loader-1x1"]
  if not base then
    base = data.raw.loader and data.raw.loader.loader
  end
  if not base then return nil end

  local entity = table.deepcopy(base)
  entity.name = name
  entity.minable = {mining_time = 0.1, result = name}
  entity.next_upgrade = nil
  entity.hidden = false
  return entity
end

local function loader_recipe(name, belt, order)
  return {
    type = "recipe",
    name = name,
    categories = {"crafting"},
    enabled = true,
    energy_required = 1,
    ingredients = {
      {type = "item", name = belt, amount = 1},
      {type = "item", name = "iron-gear-wheel", amount = 2}
    },
    results = {
      {type = "item", name = name, amount = 1}
    },
    allow_productivity = true,
    order = "mir-loader-" .. order
  }
end

local prototypes = {
  loader_item(loader_names[1], "a"),
  loader_item(loader_names[2], "b"),
  loader_item(loader_names[3], "c"),
  loader_item(loader_names[4], "d"),
  loader_recipe("aai-loader", "transport-belt", "a"),
  loader_recipe("aai-fast-loader", "fast-transport-belt", "b"),
  loader_recipe("aai-express-loader", "express-transport-belt", "c"),
  loader_recipe("aai-turbo-loader", "express-transport-belt", "d")
}

for _, name in ipairs(loader_names) do
  local entity = loader_entity(name)
  if entity then table.insert(prototypes, entity) end
end

data:extend(prototypes)
