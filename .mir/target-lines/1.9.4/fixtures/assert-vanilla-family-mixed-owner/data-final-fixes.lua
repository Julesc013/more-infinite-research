local techs = data.raw.technology or {}

local function fail(message)
  error("MIR mixed family owner validation failed: " .. message)
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local recipe_name = "mir-fixture-mixed-owner-rocket-fuel"
if has_recipe_productivity_effect(techs["rocket-fuel-productivity"], recipe_name) then
  fail("mixed owner change values should not adopt " .. recipe_name .. ".")
end

if not has_recipe_productivity_effect(techs["recipe-prod-research_rocket_fuel-1"], recipe_name) then
  fail("mixed owner change values should fall back to MIR generation for " .. recipe_name .. ".")
end
