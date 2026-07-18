local entity = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
entity.name = "mir-synthetic-recipe-machine"
entity.minable = {mining_time = 0.1, result = "mir-synthetic-recipe-machine"}
entity.next_upgrade = nil

local item = {
  type = "item",
  name = "mir-synthetic-recipe-machine",
  icon = "__base__/graphics/icons/assembling-machine-2.png",
  icon_size = 64,
  subgroup = "production-machine",
  order = "mir-synthetic-recipe-machine",
  place_result = "mir-synthetic-recipe-machine",
  stack_size = 50
}

local filler_item = {
  type = "item",
  name = "mir-synthetic-recipe-filler",
  icon = "__base__/graphics/icons/iron-plate.png",
  icon_size = 64,
  subgroup = "raw-material",
  order = "mir-synthetic-recipe-filler",
  stack_size = 100
}

data:extend({entity, item, filler_item})

-- Keep the engine-owned fixture focused on high candidate fanout. The assertion
-- separately indexes 100000 in-memory recipe prototypes through MIR's exact
-- production canonicalizer without crossing Factorio's 65535 prototype limit.
local TOTAL = 1000
local random_order = mods and mods["mir-fixture-synthetic-scale-random-order"] ~= nil

local function permuted_index(position)
  if not random_order then return position end
  return ((position * 7919 + 4729) % TOTAL) + 1
end

local chunk = {}
for position = 1, TOTAL do
  local index = permuted_index(position)
  table.insert(chunk, {
    type = "recipe",
    name = string.format("mir-synthetic-scale-recipe-%06d", index),
    enabled = true,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{
      type = "item",
      name = index <= 1000 and "mir-synthetic-recipe-machine" or "mir-synthetic-recipe-filler",
      amount = 1
    }},
    allow_productivity = true
  })

  if #chunk >= 1000 then
    data:extend(chunk)
    chunk = {}
  end
end
if #chunk > 0 then data:extend(chunk) end
