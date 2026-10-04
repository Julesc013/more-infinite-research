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

-- Maximum base quantity, before probability, extra item rolls or productivity
-- exclusions. Native products ignore ranges when amount is declared and clamp
-- a reversed ranged maximum to its minimum. Both the fact index and carrier
-- guard must retain that possible return quantity.
function M.maximum_base_result_amount(entry)
  if type(entry) ~= "table" then return 1 end
  local amount = entry.amount or entry[2]
  if amount ~= nil then return tonumber(amount) or 1 end
  local maximum = tonumber(entry.amount_max) or tonumber(entry.amount_min) or 1
  local minimum = tonumber(entry.amount_min) or maximum
  return math.max(minimum, maximum)
end

function M.productivity_excluded_amount(entry, profile)
  if type(entry) ~= "table" then return 0 end
  if entry.ignored_by_productivity ~= nil then
    return tonumber(entry.ignored_by_productivity) or 0
  end
  local shapes = profile and profile.prototype_shapes or {}
  local product_defaults = shapes.product_property_defaults or {}
  if product_defaults.ignored_by_productivity == "ignored_by_stats" then
    return tonumber(entry.ignored_by_stats) or 0
  end
  return 0
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
