local techs = data.raw.technology or {}

local function fail(message)
  error("MIR Plates n Circuit Productivity compatibility validation failed: " .. message)
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

local function assert_absent(tech_name)
  if techs[tech_name] then
    fail("expected competing technology to be removed: " .. tech_name)
  end
end

local function assert_recipe_owner(recipe_name, expected_owner)
  local owner = techs[expected_owner]
  if not owner then
    fail("missing expected owner " .. expected_owner .. " for " .. recipe_name)
  end
  if not has_recipe_productivity_effect(owner, recipe_name) then
    fail("expected " .. expected_owner .. " to own " .. recipe_name)
  end

  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= expected_owner then
    fail("recipe " .. recipe_name .. " should have exactly one infinite owner. Expected "
      .. expected_owner .. ", got: " .. table.concat(owners, ", "))
  end
end

for _, tech_name in ipairs({
  "basic-plate-productivity",
  "electric-circuit-productivity",
  "advanced-circuit-productivity"
}) do
  assert_absent(tech_name)
end

for _, expectation in ipairs({
  { recipe = "copper-plate", owner = "recipe-prod-research_copper-1" },
  { recipe = "iron-plate", owner = "recipe-prod-research_iron-1" },
  { recipe = "electronic-circuit", owner = "recipe-prod-research_electronic_circuit-1" },
  { recipe = "advanced-circuit", owner = "recipe-prod-research_advanced_circuit-1" }
}) do
  assert_recipe_owner(expectation.recipe, expectation.owner)
end

assert_recipe_owner("iron-gear-wheel", "recipe-prod-external-prefix-owner")

local dependent = techs["mir-fixture-productivity-dependent"]
if not dependent then fail("missing productivity replacement dependent") end
local prerequisites = {}
for _, name in ipairs(dependent.prerequisites or {}) do prerequisites[name] = true end
if prerequisites["basic-plate-productivity"] then
  fail("dependent retained removed competing productivity prerequisite")
end
if not prerequisites["recipe-prod-research_copper-1"]
  or not prerequisites["recipe-prod-research_iron-1"] then
  fail("dependent was not rewired to all MIR productivity replacements")
end
