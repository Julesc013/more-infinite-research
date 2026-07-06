local prototypes = {}

local base_drill = data.raw["mining-drill"] and data.raw["mining-drill"]["electric-mining-drill"]
if base_drill then
  local drill = table.deepcopy(base_drill)
  drill.name = "big-mining-drill"
  drill.minable = {mining_time = 0.3, result = "big-mining-drill"}
  drill.next_upgrade = nil
  table.insert(prototypes, drill)
end

table.insert(prototypes,
  {
    type = "item",
    name = "big-mining-drill",
    icon = "__base__/graphics/icons/electric-mining-drill.png",
    icon_size = 64,
    subgroup = "extraction-machine",
    order = "mir-big-mining-drill",
    place_result = "big-mining-drill",
    stack_size = 50
  })

table.insert(prototypes,
  {
    type = "recipe",
    name = "big-mining-drill",
    categories = {"crafting"},
    enabled = true,
    energy_required = 5,
    ingredients = {
      {type = "item", name = "electric-mining-drill", amount = 1},
      {type = "item", name = "steel-plate", amount = 10}
    },
    results = {
      {type = "item", name = "big-mining-drill", amount = 1}
    },
    allow_productivity = true
  })

data:extend(prototypes)
