local prototypes = {}

local function clone_entity(prototype_type, source_name, name, result)
  local source = data.raw[prototype_type] and data.raw[prototype_type][source_name]
  if not source then return end
  local entity = table.deepcopy(source)
  entity.name = name
  entity.minable = {mining_time = 0.1, result = result}
  entity.next_upgrade = nil
  table.insert(prototypes, entity)
end

local function add_item(name, icon, subgroup, place_result)
  table.insert(prototypes, {
    type = "item",
    name = name,
    icon = icon,
    icon_size = 64,
    subgroup = subgroup,
    order = "mir-semantic-" .. name,
    place_result = place_result,
    stack_size = 50
  })
end

local function add_recipe(name, result, ingredient)
  table.insert(prototypes, {
    type = "recipe",
    name = name,
    categories = {"crafting"},
    enabled = true,
    ingredients = {{type = "item", name = ingredient or "iron-plate", amount = 1}},
    results = {{type = "item", name = result, amount = 1}},
    allow_productivity = true
  })
end

if data.raw["loader-1x1"] and data.raw["loader-1x1"]["loader-1x1"] then
  clone_entity("loader-1x1", "loader-1x1", "opaque-transfer-node", "opaque-transfer-node")
else
  clone_entity("loader", "loader", "opaque-transfer-node", "opaque-transfer-node")
end
add_item("opaque-transfer-node", "__base__/graphics/icons/transport-belt.png", "belt", "opaque-transfer-node")
add_recipe("assemble-alpha", "opaque-transfer-node", "transport-belt")

clone_entity("mining-drill", "electric-mining-drill", "opaque-extractor", "opaque-extractor")
add_item("opaque-extractor", "__base__/graphics/icons/electric-mining-drill.png", "extraction-machine", "opaque-extractor")
add_recipe("assemble-beta", "opaque-extractor", "electric-mining-drill")

clone_entity("furnace", "stone-furnace", "opaque-smelter", "opaque-smelter")
add_item("opaque-smelter", "__base__/graphics/icons/stone-furnace.png", "smelting-machine", "opaque-smelter")
add_recipe("assemble-gamma", "opaque-smelter", "stone-furnace")

clone_entity("accumulator", "accumulator", "opaque-charge-bank", "opaque-charge-bank")
add_item("opaque-charge-bank", "__base__/graphics/icons/accumulator.png", "energy", "opaque-charge-bank")
add_recipe("assemble-delta", "opaque-charge-bank", "battery")

clone_entity("inserter", "inserter", "opaque-hand", "opaque-hand")
add_item("opaque-hand", "__base__/graphics/icons/inserter.png", "inserter", "opaque-hand")
add_recipe("assemble-epsilon", "opaque-hand", "iron-gear-wheel")

clone_entity("lab", "lab", "opaque-research-device", "opaque-research-device")
add_item("opaque-research-device", "__base__/graphics/icons/lab.png", "production-machine", "opaque-research-device")
add_recipe("assemble-zeta", "opaque-research-device", "electronic-circuit")

local source_module = data.raw.module and data.raw.module["speed-module"]
if source_module then
  local module = table.deepcopy(source_module)
  module.name = "opaque-enhancer"
  module.tier = 4
  module.order = "mir-semantic-opaque-enhancer"
  table.insert(prototypes, module)
  add_recipe("assemble-eta", "opaque-enhancer", "speed-module")
end

data:extend(prototypes)
