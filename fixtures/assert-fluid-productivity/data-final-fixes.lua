local techs = data.raw.technology or {}
local recipes = data.raw.recipe or {}

local function fail(message)
  error("MIR fluid productivity validation failed: " .. message)
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local function recipe_productivity_owners(recipe_name)
  local owners = {}
  for tech_name, tech in pairs(techs) do
    if tech.max_level == "infinite" and has_recipe_productivity_effect(tech, recipe_name) then
      table.insert(owners, tech_name)
    end
  end
  table.sort(owners)
  return owners
end

local function assert_recipe_owner(recipe_name, expected_owner)
  if not recipes[recipe_name] then return end

  local owner = techs[expected_owner]
  if not owner or owner.max_level ~= "infinite" then
    fail("missing expected infinite productivity owner " .. expected_owner .. " for recipe " .. recipe_name .. ".")
  end

  if not has_recipe_productivity_effect(owner, recipe_name) then
    fail("expected owner " .. expected_owner .. " does not cover recipe " .. recipe_name .. ".")
  end

  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= expected_owner then
    fail("recipe " .. recipe_name .. " should have exactly one infinite productivity owner. Expected "
      .. expected_owner .. ", got: " .. table.concat(owners, ", "))
  end
end

local function assert_recipe_not_owned_by(recipe_name, owner_name)
  if not recipes[recipe_name] then return end
  if has_recipe_productivity_effect(techs[owner_name], recipe_name) then
    fail(owner_name .. " should not cover recipe " .. recipe_name .. ".")
  end
end

for _, recipe_name in ipairs({
  "basic-oil-processing",
  "advanced-oil-processing",
  "coal-liquefaction",
  "simple-coal-liquefaction"
}) do
  assert_recipe_owner(recipe_name, "recipe-prod-research_oil_processing_productivity-1")
end

for _, recipe_name in ipairs({
  "heavy-oil-cracking",
  "light-oil-cracking"
}) do
  assert_recipe_owner(recipe_name, "recipe-prod-research_oil_cracking_productivity-1")
end

for _, recipe_name in ipairs({
  "lubricant",
  "biolubricant"
}) do
  assert_recipe_owner(recipe_name, "recipe-prod-research_lubricant_productivity-1")
end

assert_recipe_owner("sulfuric-acid", "recipe-prod-research_sulfuric_acid_productivity-1")

for _, recipe_name in ipairs({
  "thruster-fuel",
  "advanced-thruster-fuel"
}) do
  assert_recipe_owner(recipe_name, "recipe-prod-research_thruster_fuel_productivity-1")
end

for _, recipe_name in ipairs({
  "thruster-oxidizer",
  "advanced-thruster-oxidizer"
}) do
  assert_recipe_owner(recipe_name, "recipe-prod-research_thruster_oxidizer_productivity-1")
end

for _, barrel_recipe in ipairs({
  "empty-lubricant-barrel",
  "empty-sulfuric-acid-barrel"
}) do
  assert_recipe_not_owned_by(barrel_recipe, "recipe-prod-research_lubricant_productivity-1")
  assert_recipe_not_owned_by(barrel_recipe, "recipe-prod-research_sulfuric_acid_productivity-1")
end
