local techs = data.raw.technology or {}

local function fail(message)
  error("MIR prepatched family owner validation failed: " .. message)
end

local function recipe_effect_count(tech, recipe_name)
  local count = 0
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      count = count + 1
    end
  end
  return count
end

local owner = techs["rocket-fuel-productivity"]
if recipe_effect_count(owner, "mir-fixture-prepatched-rocket-fuel") ~= 1 then
  fail("expected exactly one vanilla owner effect for mir-fixture-prepatched-rocket-fuel.")
end

if techs["recipe-prod-research_rocket_fuel-1"] then
  fail("prepatched exact owner should not leave a residual MIR rocket fuel productivity technology.")
end
