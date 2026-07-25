local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local active_mods = require("prototypes.mir.platform.factorio.mods")
local stream_registry = require("prototypes.mir.streams.registry")

local M = {}

local function enable_recipe(recipe)
  recipe.allow_productivity = true
  if type(recipe.normal) == "table" then recipe.normal.allow_productivity = true end
  if type(recipe.expensive) == "table" then recipe.expensive.allow_productivity = true end
end

function M.apply()
  local changed = {}
  local recipes = data_raw.prototypes("recipe")
  local streams = stream_registry.view()

  for _, stream_key in ipairs(stream_registry.sorted_keys()) do
    local spec = streams[stream_key]
    for _, permission in ipairs(spec.productivity_permission_recipes or {}) do
      if active_mods.all_exist(permission.required_mods) then
        local recipe = recipes[permission.name]
        if recipe then
          enable_recipe(recipe)
          table.insert(changed, {
            recipe = permission.name,
            stream_key = stream_key
          })
        end
      end
    end
  end

  return {
    changed_count = #changed,
    changed = changed
  }
end

return M
