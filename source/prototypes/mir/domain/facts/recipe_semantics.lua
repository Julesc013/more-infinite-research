local M = {}

local FALLBACK_DEFAULTS = {
  allow_productivity = false,
  allow_quality = true,
  maximum_productivity = 3.0
}

local function defaults(profile)
  local shapes = profile and profile.prototype_shapes or {}
  return shapes.recipe_property_defaults or FALLBACK_DEFAULTS
end

local function declared(recipe, definition, field)
  if definition and definition[field] ~= nil then return definition[field] end
  if recipe and definition ~= recipe and recipe[field] ~= nil then return recipe[field] end
  return nil
end

function M.resolve(recipe, definition, profile)
  recipe = recipe or {}
  definition = definition or recipe
  local target_defaults = defaults(profile)
  local declared_allow_productivity = declared(recipe, definition, "allow_productivity")
  local declared_allow_quality = declared(recipe, definition, "allow_quality")
  local declared_maximum_productivity = declared(recipe, definition, "maximum_productivity")
  return {
    declared_allow_productivity = declared_allow_productivity,
    effective_allow_productivity = declared_allow_productivity == nil
      and target_defaults.allow_productivity
      or declared_allow_productivity,
    declared_allow_quality = declared_allow_quality,
    effective_allow_quality = declared_allow_quality == nil
      and target_defaults.allow_quality
      or declared_allow_quality,
    declared_maximum_productivity = declared_maximum_productivity,
    effective_maximum_productivity = declared_maximum_productivity == nil
      and target_defaults.maximum_productivity
      or declared_maximum_productivity
  }
end

return M
