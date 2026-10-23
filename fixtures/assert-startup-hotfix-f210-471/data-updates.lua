-- Representative inputs, not a reporter's exact mod closure.
local pack = "automation-science-pack"
local original = assert(data.raw.recipe[pack])
local circular, seed = table.deepcopy(original), table.deepcopy(original)
circular.name, circular.enabled = "a-mir471-circular-science", false
seed.name, seed.enabled = "z-mir471-seeded-science", false
data.raw.recipe[pack] = nil
for _, technology in pairs(data.raw.technology) do
  local effects = {}
  for _, effect in ipairs(technology.effects or {}) do
    if effect.type ~= "unlock-recipe" or effect.recipe ~= pack then effects[#effects + 1] = effect end
  end
  technology.effects = effects
end
-- The host control separately exercises throwing unresolved owners. Native
-- input uses valid science: Factorio independently rejects a technology with
-- no accepting lab, and MIR independently rejects a globally unbound pack.
data:extend({circular, seed,
  {type = "technology", name = "mir471-circular-owner", icon = "__base__/graphics/technology/automation.png", icon_size = 256,
    unit = {count = 10, time = 1, ingredients = {{pack, 1}}},
    effects = {{type = "unlock-recipe", recipe = circular.name}}},
  {type = "technology", name = "mir471-seed-owner", icon = "__base__/graphics/technology/automation.png", icon_size = 256,
    research_trigger = {type = "craft-item", item = "iron-plate", count = 1},
    effects = {{type = "unlock-recipe", recipe = seed.name}}},
  {type = "technology", name = "mir471-unrelated-infinite-61", icon = "__base__/graphics/technology/automation.png", icon_size = 256,
    max_level = "infinite", unit = {count_formula = "100*L", time = 1, ingredients = {{pack, 1}}},
    effects = {{type = "nothing", effect_description = "Unrelated unresolved foreign owner control"}}}
})
