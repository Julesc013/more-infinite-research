local techs = data.raw.technology or {}

local function fail(message)
  error("MIR Plates n Circuit blocked-owner validation failed: " .. message)
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

if not techs["basic-plate-productivity"] then
  fail("expected blocked combined competing technology to remain")
end

if not techs["external-copper-productivity"] then
  fail("expected external copper productivity owner to remain")
end

if has_recipe_productivity_effect(techs["recipe-prod-research_iron-1"], "iron-plate") then
  fail("MIR should not generate duplicate iron productivity while the combined competitor remains authoritative")
end

if has_recipe_productivity_effect(techs["recipe-prod-research_copper-1"], "copper-plate") then
  fail("MIR should not generate duplicate copper productivity while external owners remain authoritative")
end

local iron_owners = recipe_productivity_owners("iron-plate")
if #iron_owners ~= 1 or iron_owners[1] ~= "basic-plate-productivity" then
  fail("iron-plate should remain owned only by the combined competitor; got: " .. table.concat(iron_owners, ", "))
end

local copper_owners = recipe_productivity_owners("copper-plate")
if #copper_owners ~= 2 or copper_owners[1] ~= "basic-plate-productivity" or copper_owners[2] ~= "external-copper-productivity" then
  fail("copper-plate should remain owned by the two external fixture technologies; got: " .. table.concat(copper_owners, ", "))
end
