local techs = data.raw.technology or {}
local recipes = data.raw.recipe or {}
local labs = data.raw.lab or {}

local tech_name = "recipe-prod-research_air_scrubbing_clean_filter-1"
local allowed = {
  ["atan-pollution-filter"] = true,
  ["atan-spore-filter"] = true
}
local denied = {
  "atan-pollution-scrubbing",
  "atan-spore-scrubbing",
  "atan-pollution-filter-cleaning",
  "atan-spore-filter-cleaning",
  "atan-filter-resin"
}

local function fail(message)
  error("MIR Air Scrubbing validation failed: " .. message)
end

local function has_prerequisite(tech, prerequisite)
  for _, name in ipairs((tech and tech.prerequisites) or {}) do
    if name == prerequisite then return true end
  end
  return false
end

local function ingredient_names(tech)
  local out = {}
  for _, ingredient in ipairs(((tech and tech.unit) and tech.unit.ingredients) or {}) do
    local name = ingredient.name or ingredient[1]
    if name then out[name] = true end
  end
  return out
end

local function lab_accepts_all(science)
  for _, lab in pairs(labs) do
    local accepted = {}
    for _, input in ipairs(lab.inputs or {}) do accepted[input] = true end
    local ok = true
    for pack, _ in pairs(science) do
      if not accepted[pack] then
        ok = false
        break
      end
    end
    if ok then return true end
  end
  return false
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

local tech = techs[tech_name]
if not tech then fail("missing generated technology " .. tech_name .. ".") end
if tech.max_level ~= "infinite" then fail(tech_name .. " is not infinite.") end
if tech.upgrade ~= true then fail(tech_name .. " is not marked as an upgrade.") end
for _, prerequisite in ipairs({"atan-pollution-scrubbing", "atan-spore-scrubbing"}) do
  if not has_prerequisite(tech, prerequisite) then
    fail(tech_name .. " should require the Air Scrubbing unlock technology " .. prerequisite .. ".")
  end
end

local science = ingredient_names(tech)
for _, pack in ipairs({"automation-science-pack", "logistic-science-pack", "chemical-science-pack"}) do
  if not science[pack] then fail(tech_name .. " is missing derived science pack " .. pack .. ".") end
end
if not lab_accepts_all(science) then
  fail(tech_name .. " science pack set is not accepted by any active lab.")
end

local seen = {}
for _, effect in ipairs(tech.effects or {}) do
  if effect.type == "change-recipe-productivity" then
    if not allowed[effect.recipe] then
      fail(tech_name .. " should not target denied or unknown recipe " .. tostring(effect.recipe) .. ".")
    end
    if math.abs((tonumber(effect.change) or 0) - 0.05) > 0.000000001 then
      fail(tech_name .. " should use +0.05 for " .. tostring(effect.recipe) .. ".")
    end
    seen[effect.recipe] = true
  end
end

for recipe_name, _ in pairs(allowed) do
  if not recipes[recipe_name] then fail("fixture recipe missing: " .. recipe_name) end
  if not seen[recipe_name] then fail(tech_name .. " does not cover allowed recipe " .. recipe_name .. ".") end
  local owners = recipe_productivity_owners(recipe_name)
  if #owners ~= 1 or owners[1] ~= tech_name then
    fail(recipe_name .. " should have exactly one infinite owner, got " .. table.concat(owners, ", ") .. ".")
  end
end

for _, recipe_name in ipairs(denied) do
  if not recipes[recipe_name] then fail("fixture recipe missing: " .. recipe_name) end
  if has_recipe_productivity_effect(tech, recipe_name) then
    fail(tech_name .. " should not cover denied or unknown recipe " .. recipe_name .. ".")
  end
  local owners = recipe_productivity_owners(recipe_name)
  if #owners > 0 then
    fail(recipe_name .. " should have no infinite recipe-productivity owner, got " .. table.concat(owners, ", ") .. ".")
  end
end
