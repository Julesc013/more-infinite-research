local techs = data.raw.technology or {}

local function fail(message)
  error("MIR vanilla family adoption validation failed: " .. message)
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
  local owner = techs[expected_owner]
  if not owner then
    fail("missing expected productivity owner " .. expected_owner .. " for " .. recipe_name .. ".")
  end
  if not has_recipe_productivity_effect(owner, recipe_name) then
    fail("expected " .. expected_owner .. " to own " .. recipe_name .. ".")
  end

  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= expected_owner then
    fail("recipe " .. recipe_name .. " should have exactly one infinite owner. Expected "
      .. expected_owner .. ", got: " .. table.concat(owners, ", "))
  end
end

local function assert_recipe_has_no_infinite_owner(recipe_name)
  local owners = recipe_productivity_owners(recipe_name)
  if #owners > 0 then
    fail("recipe " .. recipe_name .. " should not have an infinite productivity owner; got: "
      .. table.concat(owners, ", "))
  end
end

local function assert_technology_absent(tech_name)
  if techs[tech_name] then
    fail("unexpected residual MIR productivity technology " .. tech_name .. ".")
  end
end

for _, expectation in ipairs({
  { recipe = "mir-fixture-adopt-rocket-fuel", owner = "rocket-fuel-productivity" },
  { recipe = "mir-fixture-adopt-low-density-structure", owner = "low-density-structure-productivity" },
  { recipe = "mir-fixture-adopt-plastic-bar", owner = "plastic-bar-productivity" },
  { recipe = "mir-fixture-adopt-processing-unit", owner = "processing-unit-productivity" },
  { recipe = "mir-fixture-adopt-steel-plate", owner = "steel-plate-productivity" }
}) do
  assert_recipe_owner(expectation.recipe, expectation.owner)
end

assert_recipe_has_no_infinite_owner("mir-fixture-no-productivity-rocket-fuel")
for _, recipe_name in ipairs({
  "mir-fixture-scrap-copper-plate-recovery",
  "mir-fixture-scrap-iron-plate-recovery",
  "mir-fixture-scrap-steel-plate-recovery"
}) do
  assert_recipe_has_no_infinite_owner(recipe_name)
end

for _, tech_name in ipairs({
  "recipe-prod-research_rocket_fuel-1",
  "recipe-prod-research_low_density_structure-1",
  "recipe-prod-research_plastic-1",
  "recipe-prod-research_processing_unit-1",
  "recipe-prod-research_steel-1"
}) do
  assert_technology_absent(tech_name)
end

local adoption_data = data.raw["mod-data"]
  and data.raw["mod-data"]["more-infinite-research-productivity-family-adoption"]
  and data.raw["mod-data"]["more-infinite-research-productivity-family-adoption"].data

if not (adoption_data and adoption_data.version == 2 and adoption_data.binding_count == 5
    and adoption_data.adopted == true and adoption_data.adopted_count >= 5) then
  fail("expected adoption mod-data to report at least five adopted recipes.")
end

local signature = tostring(adoption_data.signature or "")
for _, fragment in ipairs({
  "schema=2|stream=research_rocket_fuel|owner=rocket-fuel-productivity|operation=adopt_native_owner_effects|configured=|effects=1|output=",
  "schema=2|stream=research_low_density_structure|owner=low-density-structure-productivity|operation=adopt_native_owner_effects|configured=|effects=1|output=",
  "schema=2|stream=research_plastic|owner=plastic-bar-productivity|operation=adopt_native_owner_effects|configured=|effects=1|output=",
  "schema=2|stream=research_processing_unit|owner=processing-unit-productivity|operation=adopt_native_owner_effects|configured=|effects=1|output=",
  "schema=2|stream=research_steel|owner=steel-plate-productivity|operation=adopt_native_owner_effects|configured=|effects=1|output="
}) do
  if not string.find(signature, fragment, 1, true) then
    fail("expected adoption signature to include " .. fragment .. "; got " .. signature)
  end
end
