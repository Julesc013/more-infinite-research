local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

local unlockers_by_recipe = nil

local function build_index()
  if unlockers_by_recipe then return unlockers_by_recipe end

  unlockers_by_recipe = {}
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

function M.for_recipe(recipe_name)
  local out = {}
  for _, technology_name in ipairs(build_index()[recipe_name] or {}) do
    table.insert(out, technology_name)
  end
  return out
end

return M
