-- Finite F210 selection for the two Base productivity seeds superseded by
-- Bob's revamp routes.  This module owns neither research identities nor the
-- recipe pass; the caller supplies its returned replacement-family set to the
-- existing one-pass product-target extension.
local target = require("platform.target")

local M = {}

local REQUIRED_PROVIDERS = {"bobplates", "bobrevamp"}
local ANGEL_CONFLICT = "angelssmelting"

local function has_result(recipe, expected_type, expected_name)
  if type(recipe) ~= "table" or type(recipe.results) ~= "table" then return false end
  for _, result in ipairs(recipe.results) do
    if type(result) == "table" and result.type == expected_type and result.name == expected_name then
      return true
    end
  end
  return false
end

local function has_ingredient(recipe, expected_type, expected_name)
  if type(recipe) ~= "table" or type(recipe.ingredients) ~= "table" then return false end
  for _, ingredient in ipairs(recipe.ingredients) do
    if type(ingredient) == "table" and ingredient.type == expected_type and ingredient.name == expected_name then
      return true
    end
  end
  return false
end

local function require_route(recipes, name, expected_type, expected_name)
  local recipe = recipes[name]
  if not has_result(recipe, expected_type, expected_name) then
    error("MIR Bob productivity route changed: " .. name, 3)
  end
end

function M.select(active_mods)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or target.minimum_base ~= "2.1.23"
      or type(active_mods) ~= "table" then
    return nil
  end
  for _, provider in ipairs(REQUIRED_PROVIDERS) do
    if active_mods[provider] == nil then return nil end
  end
  -- Bob+Angel has separately captured sulfur/acid vectors.  This small
  -- profile must not replace them with the ordinary full-Bob collector pass.
  if active_mods[ANGEL_CONFLICT] ~= nil then return nil end
  return active_mods["space-age"] ~= nil and "space-age" or "base"
end

function M.replacement_product_target_families(active_mods)
  if M.select(active_mods) == nil then return {} end
  return {
    research_sulfur = true,
    research_sulfuric_acid_productivity = true,
  }
end

-- Preflight exactly the local suppression and named-route facts consumed by
-- this profile.  It intentionally does not inspect unlock graphs, labs,
-- settings from unrelated providers, or arbitrary recipe families.
function M.preflight(raw, active_mods)
  local profile = M.select(active_mods)
  if profile == nil then return nil end
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR Bob productivity requires recipe prototypes", 2)
  end
  local recipes = raw.recipe
  local sulfur, acid = recipes.sulfur, recipes["sulfuric-acid"]
  if type(sulfur) ~= "table" or sulfur.hidden ~= true then
    error("MIR Bob productivity suppression changed: sulfur", 2)
  end
  if type(acid) ~= "table" or acid.hidden ~= true then
    error("MIR Bob productivity suppression changed: sulfuric-acid", 2)
  end
  require_route(recipes, "bob-sulfur-2", "item", "sulfur")
  require_route(recipes, "bob-sulfur-3", "item", "sulfur")
  require_route(recipes, "bob-sulfuric-acid-2", "fluid", "sulfuric-acid")
  require_route(recipes, "bob-sulfuric-acid-3", "fluid", "sulfuric-acid")
  if profile == "space-age" then
    require_route(recipes, "biosulfur", "item", "sulfur")
    local neutralisation = recipes["acid-neutralisation"]
    if type(neutralisation) ~= "table"
        or not has_ingredient(neutralisation, "fluid", "sulfuric-acid") then
      error("MIR Bob productivity route changed: acid-neutralisation", 2)
    end
  end
  return profile
end

return M
