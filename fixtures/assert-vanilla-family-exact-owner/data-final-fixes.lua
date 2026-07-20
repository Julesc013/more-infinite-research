local techs = data.raw.technology or {}

local function fail(message)
  error("MIR exact owner family validation failed: " .. message)
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

local recipe_name = "mir-fixture-exact-owned-rocket-fuel"
if not has_recipe_productivity_effect(techs["mir-fixture-exact-owned-rocket-fuel-productivity"], recipe_name) then
  fail("expected fixture exact owner to keep " .. recipe_name .. ".")
end

if has_recipe_productivity_effect(techs["rocket-fuel-productivity"], recipe_name) then
  fail("vanilla rocket-fuel-productivity should not adopt an exact-owned fixture recipe.")
end

if techs["recipe-prod-research_rocket_fuel-1"] then
  fail("exact-owned family recipe should not leave a residual MIR rocket fuel productivity technology.")
end

local steel_recipe_name = "mir-fixture-exact-owned-steel-plate"
if not has_recipe_productivity_effect(techs["mir-fixture-exact-owned-steel-productivity"], steel_recipe_name) then
  fail("expected fixture exact owner to keep " .. steel_recipe_name .. ".")
end

if has_recipe_productivity_effect(techs["steel-plate-productivity"], steel_recipe_name) then
  fail("vanilla steel-plate-productivity should not adopt an exact-owned fixture recipe.")
end

if techs["recipe-prod-research_steel-1"] then
  fail("exact-owned family recipe should not leave a residual MIR steel productivity technology.")
end
