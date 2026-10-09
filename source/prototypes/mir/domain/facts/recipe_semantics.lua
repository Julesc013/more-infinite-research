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

-- One category authority for recipe facts, acquisition and cap policy.
-- Variants inherit the parent only when neither category field is declared.
-- An explicit list takes precedence; an empty/invalid list invents no route.
function M.recipe_categories(recipe, definition)
  if type(recipe) ~= "table" then return {} end
  local source = type(definition) == "table" and definition or recipe
  if source ~= recipe and source.categories == nil and source.category == nil then source = recipe end
  local categories, seen = {}, {}
  local function add(category)
    if type(category) ~= "string" or category == "" then return false end
    if not seen[category] then
      seen[category] = true
      table.insert(categories, category)
    end
    return true
  end
  if source.categories ~= nil then
    if type(source.categories) ~= "table" then return {} end
    for _, category in ipairs(source.categories) do if not add(category) then return {} end end
  elseif not add(source.category == nil and "crafting" or source.category) then
    return {}
  end
  table.sort(categories)
  return categories
end

function M.has_recipe_category(recipe, wanted)
  for _, category in ipairs(M.recipe_categories(recipe)) do if category == wanted then return true end end
  return false
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

-- Baseline production, before bonus exclusions. Return true only for a
-- supported, unambiguous product that cannot occur. Unknown fields/shapes
-- retain their possible process edge; this is not a profitable-loop proof.
-- Schema-2 facts synthesize an independent probability on legacy targets,
-- so only retained authored declarations invoke the native-field gates.
function M.result_is_definitely_zero(entry, profile, canonical)
  if type(entry) ~= "table" then return false end
  local kind = entry.type or "item"
  if kind ~= "item" and kind ~= "fluid" then return false end
  local fields = profile and profile.prototype_shapes and profile.prototype_shapes.product_probability_fields or {}
  local function supports(field)
    for _, declared_field in ipairs(fields) do if declared_field == field then return true end end
    return false
  end
  local independent, legacy = entry.independent_probability, entry.probability
  if canonical then
    independent, legacy = entry.declared_independent_probability, entry.declared_probability
  end
  if independent ~= nil and not supports("independent_probability")
    or legacy ~= nil and not supports("probability")
    or entry.shared_probability ~= nil and not supports("shared_probability")
    or entry.extra_count_fraction ~= nil and (kind ~= "item" or not supports("extra_count_fraction")) then return false end
  local function finite_nonnegative(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
  end
  local amount = entry.amount
  if amount == nil then amount = entry[2] end
  if amount == nil then
    if not finite_nonnegative(entry.amount_min) or not finite_nonnegative(entry.amount_max) then return false end
    amount = math.max(entry.amount_min, entry.amount_max)
  end
  if not finite_nonnegative(amount) then return false end
  local extra = entry.extra_count_fraction
  if extra == nil then extra = 0 end
  if not finite_nonnegative(extra) or extra > 1 then return false end
  local probability = entry.independent_probability
  if probability == nil then probability = entry.probability end
  if probability == nil then probability = 1 end
  if not finite_nonnegative(probability) or probability > 1 then return false end
  local shared = entry.shared_probability
  if shared ~= nil and (type(shared) ~= "table"
    or not finite_nonnegative(shared.min) or not finite_nonnegative(shared.max)
    or shared.max > 1 or shared.min > shared.max) then return false end
  return probability == 0 or (shared ~= nil and shared.min == shared.max)
    or (amount == 0 and extra == 0)
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
