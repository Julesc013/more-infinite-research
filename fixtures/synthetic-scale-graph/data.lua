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

local prototypes = {entity, item}
for index = 1, 1000 do
  table.insert(prototypes, {
    type = "recipe",
    name = string.format("mir-synthetic-recipe-%04d", index),
    enabled = true,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    results = {{type = "item", name = "mir-synthetic-machine", amount = 1}},
    allow_productivity = true
  })

  local technology = table.deepcopy(data.raw.technology.automation)
  technology.name = string.format("mir-synthetic-technology-%04d", index)
  technology.hidden = true
  technology.prerequisites = index == 1 and {} or {string.format("mir-synthetic-technology-%04d", index - 1)}
  technology.effects = {}
  for effect_index = 1, 10 do
    table.insert(technology.effects, {
      type = "nothing",
      effect_description = {"", "Synthetic effect ", tostring(effect_index)}
    })
  end
  table.insert(prototypes, technology)
end

data:extend(prototypes)
