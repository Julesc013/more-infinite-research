local function fail(message)
  error("MIR trigger-output representative failed: " .. message)
end

local function same_names(actual, expected)
  local left, right = {}, {}
  for _, name in pairs(actual or {}) do left[#left + 1] = name end
  for _, name in pairs(expected or {}) do right[#right + 1] = name end
  table.sort(left)
  table.sort(right)
  if #left ~= #right then return false end
  for index, name in ipairs(right) do
    if left[index] ~= name then return false end
  end
  return true
end

local function positive_item_product(products, name)
  if type(products) ~= "table" then return false end
  for _, product in pairs(products) do
    if type(product) == "table" and product.type == "item" and product.name == name
      and type(product.amount) == "number" and product.amount > 0 then
      return true
    end
  end
  return false
end

local function recipe_outputs(recipe, name)
  return type(recipe) == "table" and positive_item_product(recipe.results, name)
end

local function has_science(technology, name)
  for _, ingredient in pairs((technology.unit and technology.unit.ingredients) or {}) do
    if (ingredient.name or ingredient[1]) == name then return true end
  end
  return false
end

local function has_prerequisite_path(technology_name, expected, visited)
  if technology_name == expected then return true end
  visited = visited or {}
  if visited[technology_name] then return false end
  visited[technology_name] = true
  local technology = (data.raw.technology or {})[technology_name]
  if type(technology) ~= "table" then return false end
  for _, prerequisite in pairs(technology.prerequisites or {}) do
    if has_prerequisite_path(prerequisite, expected, visited) then return true end
  end
  return false
end

local function accepts_emitted_ingredients(technology)
  local required = {}
  for _, ingredient in pairs((technology.unit and technology.unit.ingredients) or {}) do
    required[ingredient.name or ingredient[1]] = true
  end
  if next(required) == nil then return false end
  for _, lab in pairs((data.raw.lab or {})) do
    local supported = {}
    for _, input in pairs(lab.inputs or {}) do supported[input] = true end
    local accepts_all = true
    for pack in pairs(required) do
      if not supported[pack] then accepts_all = false; break end
    end
    if accepts_all then return true end
  end
  return false
end

local function productivity_effect(technology, recipe_name, amount)
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name
      and effect.change == amount then return true end
  end
  return false
end

local function exact_ordinary_cryogenic_input()
  local recipe = data.raw.recipe and data.raw.recipe["cryogenic-science-pack"]
  local technology = data.raw.technology and data.raw.technology["cryogenic-science-pack"]
  local trigger = technology and technology.research_trigger
  if type(recipe) ~= "table" or not recipe_outputs(recipe, "cryogenic-science-pack")
    or type(technology) ~= "table" or type(trigger) ~= "table"
    or trigger.type ~= "craft-item" or trigger.item ~= "cryogenic-plant"
    or not same_names(technology.prerequisites or {}, {"cryogenic-plant"}) then
    fail("ordinary cryogenic craft-item input changed")
  end
  local unlock_count = 0
  for _, effect in pairs(technology.effects or {}) do
    if effect.type == "unlock-recipe" and effect.recipe == "cryogenic-science-pack" then unlock_count = unlock_count + 1 end
  end
  if unlock_count ~= 1 then fail("ordinary cryogenic unlock changed") end
end
local function exact_trigger_input()
  local satellite = data.raw.item and data.raw.item.satellite
  local recipe = data.raw.recipe and data.raw.recipe["space-science-pack"]
  local technology = data.raw.technology and data.raw.technology["space-science-pack"]
  if type(satellite) ~= "table" or type(recipe) ~= "table" or type(technology) ~= "table" then
    fail("required space-science input is absent")
  end
  local trigger = technology.research_trigger
  if recipe.enabled ~= false or not recipe_outputs(recipe, "space-science-pack")
    or type(trigger) ~= "table" or trigger.type ~= "send-item-to-orbit" or trigger.item ~= "satellite"
    or not positive_item_product(satellite.rocket_launch_products, "space-science-pack")
    or not same_names(technology.prerequisites or {}, {"rocket-silo"})
    or next(technology.effects or {}) ~= nil then
    fail("target-only trigger-output input shape is not exact")
  end
end

local function assert_emitted_technology(name, recipes)
  local technology = data.raw.technology and data.raw.technology[name]
  if type(technology) ~= "table" then fail("emitted technology missing: " .. name) end
  if not has_science(technology, "space-science-pack") or not has_science(technology, "cryogenic-science-pack")
    or not has_prerequisite_path(name, "space-science-pack") then
    fail("trigger-output science/progression was not used by " .. name)
  end
  if not accepts_emitted_ingredients(technology) then
    fail("no actual lab accepts the complete emitted ingredient vector: " .. name)
  end
  for recipe_name, amount in pairs(recipes) do
    if not productivity_effect(technology, recipe_name, amount) then
      fail("emitted productivity effect is missing: " .. name .. "/" .. recipe_name)
    end
  end
  return technology
end

local function assert_ice_existing_productivity_owner(technology)
  local owner = data.raw.technology and data.raw.technology["asteroid-productivity"]
  if type(owner) ~= "table" then fail("existing asteroid productivity owner is missing") end
  for _, recipe_name in ipairs({"oxide-asteroid-crushing", "advanced-oxide-asteroid-crushing"}) do
    if productivity_effect(technology, recipe_name, 0.10) then
      fail("emitted ice productivity duplicates existing owner: " .. recipe_name)
    end
    if not productivity_effect(owner, recipe_name, 0.10) then
      fail("existing asteroid productivity owner effect is missing: " .. recipe_name)
    end
  end
end

if mods and mods["more-infinite-research"] == "4.7.21000" then
  exact_trigger_input()
  exact_ordinary_cryogenic_input()
  local ice = assert_emitted_technology("recipe-prod-research_ice-1", {})
  assert_ice_existing_productivity_owner(ice)
  assert_emitted_technology("recipe-prod-research_platform-1", {
    ["ice-platform"] = 0.10,
    ["space-platform-foundation"] = 0.05
  })
  local prototype = (data.raw["mod-data"] or {})["more-infinite-research-generation-plan-internal"]
  local plan = prototype and prototype.data
  if type(plan) ~= "table" or plan.schema ~= 3 or type(plan.validation_summary) ~= "table"
    or plan.validation_summary.valid ~= true then
    fail("accepted internal generation plan is missing")
  end
  log("[mir-trigger-output-fixture] data-stage=target binding=declared-trigger-output cryogenic=declared-recipe")
end
