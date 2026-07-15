local techs = data.raw.technology or {}
local recipes = data.raw.recipe or {}

local tech_name = "recipe-prod-research_ash_separation-1"
local allowed_recipe = "atan-ash-seperation"
local denied_recipes = {
  "atan-landfill-from-ash",
  "atan-stone-brick-from-ash",
  "atan-nutrients-from-ash",
  "atan-foundation-from-ash"
}

local function fail(message)
  error("MIR ATAN Ash validation failed: " .. message)
end

local function has_recipe_productivity_effect(tech, recipe_name)
  for _, effect in ipairs((tech and tech.effects) or {}) do
    if effect.type == "change-recipe-productivity" and effect.recipe == recipe_name then
      return true, effect.change
    end
  end
  return false, nil
end

local function recipe_productivity_owners(recipe_name)
  local owners = {}
  for owner_name, tech in pairs(techs) do
    if tech.max_level == "infinite" and has_recipe_productivity_effect(tech, recipe_name) then
      table.insert(owners, owner_name)
    end
  end
  table.sort(owners)
  return owners
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local tech = techs[tech_name]
if not tech then fail("missing generated technology " .. tech_name .. ".") end
if tech.max_level ~= "infinite" then fail(tech_name .. " is not infinite.") end
if tech.upgrade ~= true then fail(tech_name .. " is not marked as an upgrade.") end
if not has_prerequisite(tech, "atan-ash-processing") then
  fail(tech_name .. " should require the ATAN Ash unlock technology.")
end

local allowed_seen, allowed_change = has_recipe_productivity_effect(tech, allowed_recipe)
if not allowed_seen then fail(tech_name .. " does not cover " .. allowed_recipe .. ".") end
if math.abs((tonumber(allowed_change) or 0) - 0.05) > 0.000000001 then
  fail(tech_name .. " should use +0.05 for " .. allowed_recipe .. ".")
end
local allowed_owners = recipe_productivity_owners(allowed_recipe)
if #allowed_owners ~= 1 or allowed_owners[1] ~= tech_name then
  fail(allowed_recipe .. " should have exactly one infinite owner, got " .. table.concat(allowed_owners, ", ") .. ".")
end

for _, recipe_name in ipairs(denied_recipes) do
  if not recipes[recipe_name] then fail("fixture recipe missing: " .. recipe_name) end
  if has_recipe_productivity_effect(tech, recipe_name) then
    fail(tech_name .. " should not cover denied recipe " .. recipe_name .. ".")
  end
  local owners = recipe_productivity_owners(recipe_name)
  if #owners > 0 then
    fail(recipe_name .. " should have no infinite recipe-productivity owner, got " .. table.concat(owners, ", ") .. ".")
  end
end
