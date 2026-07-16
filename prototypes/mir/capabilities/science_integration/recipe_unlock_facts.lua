local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")

local M = {}
local science_pack_recipe_status_cache = nil

function M.recipe_outputs_item(recipe, item_name)
  local recipe_name = type(recipe) == "table" and recipe.name or recipe
  local fact = recipe_name and recipe_facts.view(recipe_name) or nil
  if not fact then return false end
  for _, result_name in ipairs(fact.result_names or {}) do
    if result_name == item_name then return true end
  end
  return false
end

function M.recipe_enabled_without_research(recipe)
  local recipe_name = type(recipe) == "table" and recipe.name or recipe
  local fact = recipe_name and recipe_facts.view(recipe_name) or nil
  return fact ~= nil and fact.enabled_without_research == true
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

  for _, pack_name in ipairs(lab_inputs) do
    local status = science_pack_recipe_status_cache[pack_name]
    for _, recipe_name in ipairs(recipe_facts.recipes_by_output_view(pack_name)) do
      local recipe = recipe_facts.view(recipe_name)
      status.has_recipe = true
      table.insert(status.recipes, recipe_name)
      if recipe and recipe.enabled_without_research == true then
        status.initially_available = true
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
