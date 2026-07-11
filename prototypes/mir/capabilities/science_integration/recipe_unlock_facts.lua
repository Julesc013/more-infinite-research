local deepcopy = require("prototypes.mir.core.deepcopy")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")

local M = {}
local science_pack_recipe_status_cache = nil

function M.recipe_outputs_item(recipe, item_name)
  local function matches(result)
    if not result then return false end
    local name = type(result) == "string" and result or result.name or result[1]
    return name == item_name
  end
  local function scan(def)
    if not def then return false end
    if def.results then
      for _, result in pairs(def.results) do
        if matches(result) then return true end
      end
    elseif def.result then
      return matches(def.result)
    end
    return false
  end
  if recipe.normal or recipe.expensive then return scan(recipe.normal) or scan(recipe.expensive) end
  return scan(recipe)
end

function M.recipe_enabled_without_research(recipe)
  if not recipe or recipe.hidden == true or recipe.enabled == false then return false end
  local variants = {}
  if recipe.normal then table.insert(variants, recipe.normal) end
  if recipe.expensive then table.insert(variants, recipe.expensive) end
  for _, variant in ipairs(variants) do
    if variant.enabled == false then return false end
  end
  return true
end

local function build_science_pack_recipe_status_cache()
  if science_pack_recipe_status_cache then return science_pack_recipe_status_cache end
  science_pack_recipe_status_cache = {}
  local lab_inputs = pack_registry.all_lab_inputs()
  for _, pack_name in ipairs(lab_inputs) do
    science_pack_recipe_status_cache[pack_name] = {
      has_recipe = false,
      initially_available = false,
      recipes = {}
    }
  end

  for recipe_name, recipe in pairs(data_raw.prototypes("recipe")) do
    for _, pack_name in ipairs(lab_inputs) do
      if M.recipe_outputs_item(recipe, pack_name) then
        local status = science_pack_recipe_status_cache[pack_name]
        status.has_recipe = true
        table.insert(status.recipes, recipe_name)
        if M.recipe_enabled_without_research(recipe) then status.initially_available = true end
      end
    end
  end
  for _, status in pairs(science_pack_recipe_status_cache) do table.sort(status.recipes) end
  return science_pack_recipe_status_cache
end

function M.pack_recipe_status(pack_name)
  local status = build_science_pack_recipe_status_cache()[pack_name]
  return status and deepcopy(status) or nil
end

function M.unlockers_for_recipe(recipe_name)
  return recipe_unlocks.for_recipe(recipe_name)
end

return M
