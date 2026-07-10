local pack_name = "mir-fixture-prerequisite-science-pack"
local recipe_name = "mir-fixture-prerequisite-science-pack"
local initial_pack_name = "mir-fixture-initial-science-pack"
local self_lock_pack_name = "mir-fixture-self-lock-science-pack"
local cycle_pack_a_name = "mir-fixture-cycle-science-pack-a"
local cycle_pack_b_name = "mir-fixture-cycle-science-pack-b"

local pack = {
  type = "item",
  name = pack_name,
  icon = "__base__/graphics/icons/automation-science-pack.png",
  icon_size = 64,
  subgroup = "science-pack",
  order = "z[mir-fixture-prerequisite-science-pack]",
  stack_size = 200
}

local recipe = {
  type = "recipe",
  name = recipe_name,
  enabled = false,
  ingredients = {
    {type = "item", name = "automation-science-pack", amount = 1}
  },
  results = {
    {type = "item", name = pack_name, amount = 1}
  }
}

local initial_pack = table.deepcopy(pack)
initial_pack.name = initial_pack_name
initial_pack.order = "z[mir-fixture-initial-science-pack]"

local initial_recipe = table.deepcopy(recipe)
initial_recipe.name = initial_pack_name
initial_recipe.enabled = true
initial_recipe.results = {
  {type = "item", name = initial_pack_name, amount = 1}
}

local function pack_and_recipe(name)
  local next_pack = table.deepcopy(pack)
  next_pack.name = name
  next_pack.order = "z[" .. name .. "]"
  local next_recipe = table.deepcopy(recipe)
  next_recipe.name = name
  next_recipe.results = {{type = "item", name = name, amount = 1}}
  return next_pack, next_recipe
end

local self_lock_pack, self_lock_recipe = pack_and_recipe(self_lock_pack_name)
local cycle_pack_a, cycle_recipe_a = pack_and_recipe(cycle_pack_a_name)
local cycle_pack_b, cycle_recipe_b = pack_and_recipe(cycle_pack_b_name)

local function unlocker(name, enabled, unlocked_recipe, ingredients)
  return {
    type = "technology",
    name = name,
    enabled = enabled,
    icon = "__base__/graphics/technology/automation-science-pack.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = unlocked_recipe}
    },
    unit = {
      count = 10,
      ingredients = ingredients or {{"automation-science-pack", 1}},
      time = 10
    }
  }
end

data:extend({
  pack,
  recipe,
  initial_pack,
  initial_recipe,
  unlocker("mir-fixture-disabled-initial-unlocker", false, initial_pack_name),
  unlocker("mir-fixture-00-disabled-custom-unlocker", false, recipe_name),
  unlocker("mir-fixture-custom-unlocker-a", true, recipe_name),
  unlocker("mir-fixture-custom-unlocker-b", true, recipe_name),
  self_lock_pack,
  self_lock_recipe,
  unlocker("mir-fixture-self-lock-unlocker", true, self_lock_pack_name, {{self_lock_pack_name, 1}}),
  cycle_pack_a,
  cycle_recipe_a,
  cycle_pack_b,
  cycle_recipe_b,
  unlocker("mir-fixture-cycle-unlocker-a", true, cycle_pack_a_name, {{cycle_pack_b_name, 1}}),
  unlocker("mir-fixture-cycle-unlocker-b", true, cycle_pack_b_name, {{cycle_pack_a_name, 1}}),
  unlocker("mir-fixture-no-research-mechanism-unlocker", true, recipe_name)
})

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, pack_name)
  table.insert(lab.inputs, initial_pack_name)
  table.insert(lab.inputs, self_lock_pack_name)
  table.insert(lab.inputs, cycle_pack_a_name)
  table.insert(lab.inputs, cycle_pack_b_name)
end
