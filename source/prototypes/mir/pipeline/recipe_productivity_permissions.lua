local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local active_mods = require("prototypes.mir.platform.factorio.mods")
local stream_registry = require("prototypes.mir.streams.registry")
local settings_resolver = require("prototypes.mir.settings.resolver")

local M = {}

local function has_declared_productivity_contract(recipe)
  local function declared(definition)
    if type(definition) == "table"
      and (definition.allow_productivity ~= nil or definition.maximum_productivity ~= nil) then
      return true
    end
    return false
  end
  if declared(recipe) then return true end
  for _, definition in pairs({normal = recipe.normal, expensive = recipe.expensive}) do
    if declared(definition) then return true end
  end
  return false
end

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
          local implicit_admitted = permission.only_if_implicit_productivity ~= true
            or (settings_resolver.stream_enabled(stream_key, spec)
              and not has_declared_productivity_contract(recipe))
          if implicit_admitted then
            enable_recipe(recipe)
            table.insert(changed, {
              recipe = permission.name,
              stream_key = stream_key
            })
          end
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
