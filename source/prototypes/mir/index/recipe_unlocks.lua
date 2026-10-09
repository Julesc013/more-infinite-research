local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local recipe_facts = require("prototypes.mir.index.recipe_facts")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")
local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}

local function build_index()
  local unlockers_by_recipe = {}
  local technology_names = {}
  for name, _ in pairs(data_raw.prototypes("technology")) do
    table.insert(technology_names, name)
  end
  table.sort(technology_names)

  for _, technology_name in ipairs(technology_names) do
    local technology = data_raw.technology(technology_name)
    local seen = {}
    for _, effect in ipairs((technology and technology.effects) or {}) do
      local recipe_name = effect.type == "unlock-recipe" and effect.recipe or nil
      if recipe_name and not seen[recipe_name] then
        seen[recipe_name] = true
        unlockers_by_recipe[recipe_name] = unlockers_by_recipe[recipe_name] or {}
        table.insert(unlockers_by_recipe[recipe_name], technology_name)
      end
    end
  end

  return unlockers_by_recipe
end

local function current_index()
  local context = compiler_context.current()
  local source_epoch = recipe_facts.source_epoch()
  local cached = context:state_view("recipe_unlock_index")
  if cached and cached.recipe_source_epoch == source_epoch then return cached.unlockers_by_recipe end

  local value = {
    recipe_source_epoch = source_epoch,
    unlockers_by_recipe = build_index()
  }
  if cached then
    context:replace_epoch("recipe_unlock_index", value, context:state_epoch("recipe_unlock_index"))
  else
    context:set_state("recipe_unlock_index", value)
  end
  return value.unlockers_by_recipe
end

function M.for_recipe(recipe_name)
  return deepcopy(current_index()[recipe_name] or {})
end

return M
