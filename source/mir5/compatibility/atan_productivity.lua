-- Narrow F200 ATAN productivity bindings for the captured Base and Space Age
-- variants. The module names every recipe and owner directly. It has no
-- technology scan, route inference, or prototype write authority.
local M = {}
local target = require("platform.target")

local function fail(message)
  error("MIR5 F200 ATAN productivity catalogue: " .. message, 3)
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then fail("definition contains a cycle") end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item, seen) end
  seen[value] = nil
  return out
end

local function names_match(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, name in ipairs(expected) do
    if actual[index] ~= name then return false end
  end
  return true
end

local function row_name(row)
  return type(row) == "table" and (row.name or row[1]) or nil
end

local function row_amount(row)
  return type(row) == "table" and (row.amount or row[2]) or nil
end

local function default_or(actual, expected)
  return (expected == nil or expected == "default") and (actual == nil or actual == 1) or actual == expected
end

-- A target has one captured ordered typed recipe form. Non-default catalyst,
-- range, probability, productivity-stat, and result-sharing fields describe a
-- different route even when the recipe name remains the same.
local function rows_match(actual, expected)
  if type(actual) ~= "table" or #actual ~= #expected then return false end
  for index, wanted in ipairs(expected) do
    local found = actual[index]
    if type(found) ~= "table"
      or (found.type or "item") ~= wanted.type
      or row_name(found) ~= wanted.name
      or row_amount(found) ~= wanted.amount
      or found.amount_min ~= nil or found.amount_max ~= nil
      or not default_or(found.probability, wanted.probability)
      or (found.independent_probability ~= nil and found.independent_probability ~= 1)
      or (found.shared_probability ~= nil and (type(found.shared_probability) ~= "table"
        or found.shared_probability.min ~= 0 or found.shared_probability.max ~= 1))
      or (found.catalyst_amount ~= nil and found.catalyst_amount ~= 0)
      or (found.ignored_by_productivity ~= nil and found.ignored_by_productivity ~= 0)
      or (found.extra_count_fraction ~= nil and found.extra_count_fraction ~= 0) then
      return false
    end
  end
  return true
end

local function binding_item(binding, definition)
  return binding.item or definition.item, binding.item_icon or definition.icon, binding.item_icon_size
end

local function item_matches(item, binding, definition)
  local _, icon, expected = binding_item(binding, definition)
  if type(item) ~= "table" or item.icon ~= icon then return false end
  if expected == "default" then return item.icon_size == nil or item.icon_size == definition.icon_size end
  return item.icon_size == expected
end

local function allow_productivity_matches(actual, expected)
  if expected == "not-false" then return actual ~= false end
  return actual == expected
end

local function recipe_matches(recipe, binding)
  return type(recipe) == "table"
    and recipe.enabled == binding.enabled
    and recipe.hidden ~= true
    and recipe.category == binding.category
    and recipe.energy_required == binding.energy_required
    and allow_productivity_matches(recipe.allow_productivity, binding.allow_productivity)
    and ((binding.maximum_productivity == "omitted" and recipe.maximum_productivity == nil)
      or (binding.maximum_productivity ~= "omitted" and recipe.maximum_productivity == binding.maximum_productivity))
    and rows_match(recipe.ingredients, binding.ingredients)
    and rows_match(recipe.results, binding.results)
end

local function owner_matches(owner, binding)
  if type(owner) ~= "table" or owner.enabled == false or owner.hidden == true
    or not names_match(owner.prerequisites or {}, binding.owner_prerequisites) then
    return false
  end
  local unit = owner.unit
  if type(unit) ~= "table" or unit.count ~= binding.owner_unit_count or unit.time ~= binding.owner_unit_time
    or not rows_match(unit.ingredients, binding.owner_science) then
    return false
  end
  local matching = 0
  for _, effect in ipairs(owner.effects or {}) do
    if effect.recipe == binding.recipe then
      if effect.type ~= "unlock-recipe" then return false end
      matching = matching + 1
    end
  end
  return matching == 1
end

local function bindings_for(definition)
  if type(definition.bindings) == "table" then return definition.bindings end
  return {definition.binding}
end

local function preflight(raw, definition)
  if type(raw) ~= "table" or type(raw.item) ~= "table"
    or type(raw.recipe) ~= "table" or type(raw.technology) ~= "table" then
    fail("named F200 ATAN raw prototypes are unavailable")
  end
  for _, binding in ipairs(bindings_for(definition)) do
    local item = binding.item or definition.item
    if not item_matches(raw.item[item], binding, definition) then
      fail(item .. " presentation changed")
    end
    if not recipe_matches(raw.recipe[binding.recipe], binding) then
      fail(binding.recipe .. " changed")
    end
    if not owner_matches(raw.technology[binding.owner], binding) then
      fail(binding.owner .. " no longer owns " .. binding.recipe)
    end
  end
end

-- Both variants bind the exact two relevant ATAN versions. Unrelated active
-- mods do not enter admission. Space Age is a separately captured F200 branch;
-- an unknown Space Age version and every F210 target are withheld.
function M.select(active_mods, raw)
  if type(active_mods) ~= "table" then fail("requires the data-stage mods table") end
  local profile = require("compatibility.atan_profile").select(active_mods, target)
  if not profile then return {} end
  local authored = require("research.atan_productivity")
  local definitions
  if profile == "base" then
    definitions = authored.f200_base_definitions()
  else
    definitions = authored.f200_space_age_definitions()
  end

  for _, definition in ipairs(definitions) do preflight(raw, definition) end

  local output = {}
  for index, definition in ipairs(definitions) do output[index] = copy(definition) end
  return output
end

return M
