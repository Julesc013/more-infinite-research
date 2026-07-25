local entity = table.deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
entity.name = "mir-synthetic-machine"
entity.minable = {mining_time = 0.1, result = "mir-synthetic-machine"}
entity.next_upgrade = nil

local item = {
  type = "item",
  name = "mir-synthetic-machine",
  icon = "__base__/graphics/icons/assembling-machine-2.png",
  icon_size = 64,
  subgroup = "production-machine",
  order = "mir-synthetic-machine",
  place_result = "mir-synthetic-machine",
  stack_size = 50
}

data:extend({entity, item})

-- Factorio technology prototype IDs are hard-limited to 65535. Keep the
-- materialized load below that ceiling; the assertion fixture separately feeds
-- the same compiler graph implementation 100000 in-memory planned technologies.
local TOTAL = 60000
local random_order = mods and mods["mir-fixture-synthetic-scale-random-order"] ~= nil

local function permuted_index(position)
  if not random_order then return position end
  return ((position * 7919 + 4729) % TOTAL) + 1
end

local recipe_chunk = {}
for index = 1, 1000 do
  table.insert(recipe_chunk, {
    type = "recipe",
    name = string.format("mir-synthetic-recipe-%06d", index),
    enabled = true,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = "mir-synthetic-machine", amount = 1}},
    allow_productivity = true
  })
end
data:extend(recipe_chunk)

local technology_chunk = {}
for position = 1, TOTAL do
  local index = permuted_index(position)
  local technology = table.deepcopy(data.raw.technology.automation)
  technology.name = string.format("mir-synthetic-technology-%06d", index)
  technology.hidden = true
  -- Keep the engine-owned graph shallow and acyclic. Factorio's recursive cycle
  -- checker stack-overflows on the adversarial 25000-node SCC exercised by the
  -- iterative MIR graph validator in the assertion fixture.
  technology.prerequisites = {"automation"}
  technology.effects = {{
    type = "nothing",
    effect_description = {"", "Synthetic effect ", tostring(index)}
  }}
  table.insert(technology_chunk, technology)

  if #technology_chunk >= 1000 then
    data:extend(technology_chunk)
    technology_chunk = {}
  end
end
if #technology_chunk > 0 then data:extend(technology_chunk) end
