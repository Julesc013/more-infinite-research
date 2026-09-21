local deepcopy = require("prototypes.mir.core.deepcopy")
local recipe_unlocks = require("prototypes.mir.index.recipe_unlocks")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local pack_registry = require("prototypes.mir.capabilities.science_integration.pack_registry")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local M = {}

function M.recipe_outputs_item(recipe, item_name)
  local recipe_name = type(recipe) == "table" and recipe.name or recipe
  local fact = recipe_name and recipe_facts.view(recipe_name) or nil
  if not fact then return false end
  if fact.result_identities then
    for _, result in ipairs(fact.result_identities) do
      if result.type == "item" and result.name == item_name then return true end
    end
    return false
  end
  -- Compatibility for narrow legacy fixtures that predate the typed recipe
  -- fact projection. Canonical facts always take the exact branch above.
  for _, result_name in ipairs(fact.result_names or {}) do
    if result_name == item_name then return true end
  end
  return false
end

local function recipes_by_item_output_view(item_name)
  if recipe_facts.recipes_by_output_identity_view then
    return recipe_facts.recipes_by_output_identity_view("item", item_name)
  end
  -- Narrow legacy-fixture compatibility only. A canonical index has the
  -- identity projection and therefore cannot confuse an item with a fluid
  -- sharing the same name.
  return recipe_facts.recipes_by_output_view(item_name)
end

function M.recipe_enabled_without_research(recipe)
  local recipe_name = type(recipe) == "table" and recipe.name or recipe
  local fact = recipe_name and recipe_facts.view(recipe_name) or nil
  return fact ~= nil and fact.enabled_without_research == true
end

local function build_science_pack_recipe_status_cache()
  local context = compiler_context.current()
  local source_epoch = recipe_facts.source_epoch()
  local cached = context:state_view("science_pack_recipe_status")
  if cached and cached.recipe_source_epoch == source_epoch then return cached.statuses end
  local science_pack_recipe_status_cache = {}
  local lab_inputs = pack_registry.all_lab_inputs()
  for _, pack_name in ipairs(lab_inputs) do
    science_pack_recipe_status_cache[pack_name] = {
      pack_name = pack_name,
      has_recipe = false,
      initially_available = false,
      recipes = {}
    }
  end

  for _, pack_name in ipairs(lab_inputs) do
    local status = science_pack_recipe_status_cache[pack_name]
    for _, recipe_name in ipairs(recipes_by_item_output_view(pack_name)) do
      local recipe = recipe_facts.view(recipe_name)
      status.has_recipe = true
      table.insert(status.recipes, recipe_name)
      if recipe and recipe.enabled_without_research == true then
        status.initially_available = true
      end
    end
  end
  for _, status in pairs(science_pack_recipe_status_cache) do table.sort(status.recipes) end
  local value = {
    recipe_source_epoch = source_epoch,
    statuses = science_pack_recipe_status_cache
  }
  if cached then
    context:replace_epoch("science_pack_recipe_status", value, context:state_epoch("science_pack_recipe_status"))
  else
    context:set_state("science_pack_recipe_status", value)
  end
  return value.statuses
end

function M.pack_recipe_status(pack_name)
  local status = build_science_pack_recipe_status_cache()[pack_name]
  return status and deepcopy(status) or nil
end

function M.unlockers_for_recipe(recipe_name)
  return recipe_unlocks.for_recipe(recipe_name)
end

return M
