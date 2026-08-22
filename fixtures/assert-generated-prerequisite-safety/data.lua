local pack_name = "mir-fixture-prerequisite-science-pack"
local recipe_name = "mir-fixture-prerequisite-science-pack"
local initial_pack_name = "mir-fixture-initial-science-pack"
local self_lock_pack_name = "mir-fixture-self-lock-science-pack"
local cycle_pack_a_name = "mir-fixture-cycle-science-pack-a"
local cycle_pack_b_name = "mir-fixture-cycle-science-pack-b"
local alternate_route_pack_name = "mir-fixture-alternate-route-science-pack"
local alternate_route_early_recipe_name = "mir-fixture-alternate-route-early"
local alternate_route_late_recipe_name = "mir-fixture-alternate-route-late"
local recycling_alternate_pack_name = "mir-fixture-recycling-alternate-science-pack"
local recycling_alternate_recipe_name = "mir-fixture-recycling-alternate"
local self_return_pack_name = "mir-fixture-self-return-science-pack"
local self_return_recipe_name = "mir-fixture-self-return-recycling"
local recycling_only_pack_name = "mir-fixture-recycling-only-science-pack"
local recycling_only_recipe_name = "mir-fixture-recycling-only"

local science_pack_type = data.raw.tool and data.raw.tool["automation-science-pack"] and "tool" or "item"

local pack = {
  type = science_pack_type,
  name = pack_name,
  icon = "__base__/graphics/icons/automation-science-pack.png",
  icon_size = 64,
  subgroup = "science-pack",
  order = "z[mir-fixture-prerequisite-science-pack]",
  stack_size = 200
}
if science_pack_type == "tool" then
  pack.durability = 1
  pack.durability_description_key = "description.science-pack-remaining-amount-key"
  pack.factoriopedia_durability_description_key = "description.factoriopedia-science-pack-remaining-amount-key"
  pack.durability_description_value = "description.science-pack-remaining-amount-value"
end

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
local alternate_route_pack, alternate_route_early_recipe = pack_and_recipe(alternate_route_pack_name)
alternate_route_early_recipe.name = alternate_route_early_recipe_name
local alternate_route_late_recipe = table.deepcopy(alternate_route_early_recipe)
alternate_route_late_recipe.name = alternate_route_late_recipe_name

local recycling_alternate_pack, recycling_alternate_primary_recipe =
  pack_and_recipe(recycling_alternate_pack_name)
local recycling_alternate_recipe = table.deepcopy(recycling_alternate_primary_recipe)
recycling_alternate_recipe.name = recycling_alternate_recipe_name
recycling_alternate_recipe.enabled = true
recycling_alternate_recipe.categories = {"recycling"}

local self_return_pack, self_return_recipe = pack_and_recipe(self_return_pack_name)
self_return_recipe.name = self_return_recipe_name
self_return_recipe.enabled = true
self_return_recipe.categories = {"recycling"}
self_return_recipe.ingredients = {{type = "item", name = self_return_pack_name, amount = 1}}

local recycling_only_pack, recycling_only_recipe = pack_and_recipe(recycling_only_pack_name)
recycling_only_recipe.name = recycling_only_recipe_name
recycling_only_recipe.enabled = true
recycling_only_recipe.categories = {"recycling"}

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

local fixture_prototypes = {
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
  alternate_route_pack,
  alternate_route_early_recipe,
  alternate_route_late_recipe,
  unlocker("mir-fixture-z-early-route-unlocker", true, alternate_route_early_recipe_name),
  unlocker("mir-fixture-00-late-route-unlocker", true, alternate_route_late_recipe_name),
  recycling_alternate_pack,
  recycling_alternate_primary_recipe,
  recycling_alternate_recipe,
  unlocker("mir-fixture-recycling-alternate-primary-unlocker", true, recycling_alternate_pack_name),
  self_return_pack,
  self_return_recipe,
  recycling_only_pack,
  recycling_only_recipe,
  unlocker("mir-fixture-no-research-mechanism-unlocker", true, recipe_name)
}

if not (data.raw["recipe-category"] and data.raw["recipe-category"].recycling) then
  table.insert(fixture_prototypes, 1, {type = "recipe-category", name = "recycling"})
end

data:extend(fixture_prototypes)

data.raw.technology["mir-fixture-00-late-route-unlocker"].prerequisites = {
  "mir-fixture-z-early-route-unlocker"
}

for _, lab in pairs(data.raw.lab or {}) do
  lab.inputs = lab.inputs or {}
  table.insert(lab.inputs, pack_name)
  table.insert(lab.inputs, initial_pack_name)
  table.insert(lab.inputs, self_lock_pack_name)
  table.insert(lab.inputs, cycle_pack_a_name)
  table.insert(lab.inputs, cycle_pack_b_name)
  table.insert(lab.inputs, alternate_route_pack_name)
  table.insert(lab.inputs, recycling_alternate_pack_name)
  table.insert(lab.inputs, self_return_pack_name)
  table.insert(lab.inputs, recycling_only_pack_name)
end
