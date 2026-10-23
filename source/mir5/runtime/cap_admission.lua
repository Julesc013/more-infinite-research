-- Exact runtime admission for the five published Space Age native owners.
-- This does not discover technologies or infer an owner from aggregate force
-- values. The catalogue names the candidate; this module checks its bounded
-- current prototype contract before caps may change it.
local M = {}

local INFINITE_MAX_LEVEL = 4294967295

local function exact_recipes(expected, effects, change)
  if type(effects) ~= "table" or #effects ~= #expected then return false end
  for index = 1, #expected do
    local effect = effects[index]
    if type(effect) ~= "table" or effect.type ~= "change-recipe-productivity"
        or effect.recipe ~= expected[index] or effect.change ~= change then
      return false
    end
  end
  return true
end

local function declared_contract(declaration)
  if type(declaration) ~= "table" or declaration.ownership_kind ~= "nativeowner"
      or type(declaration.id) ~= "string" or declaration.id == ""
      or declaration.native_owner_identity ~= declaration.id then
    return nil
  end
  local admission = declaration.native_admission
  if type(admission) ~= "table" or admission.effect_type ~= "change-recipe-productivity"
      or type(admission.recipes) ~= "table" or #admission.recipes == 0 then
    return nil
  end
  local recipes = {}
  for index = 1, #admission.recipes do
    local recipe = admission.recipes[index]
    if type(recipe) ~= "string" or recipe == "" or recipes[recipe] then return nil end
    recipes[recipe] = true
  end
  -- Preserve the authored order: the native prototype contract was captured
  -- as an exact ordered effect list, rather than a permissive recipe set.
  local ordered = {}
  for index = 1, #admission.recipes do ordered[index] = admission.recipes[index] end
  return ordered
end

function M.admits_native_owner(lookup, declaration, configured_change)
  if type(lookup) ~= "function" then return false end
  local change = configured_change == nil and 0.1 or configured_change
  if type(change) ~= "number" or change ~= change or change <= 0 or change == math.huge then return false end
  local recipes = declared_contract(declaration)
  if recipes == nil then return false end
  local ok, technology = pcall(lookup, declaration.id)
  if not ok or technology == nil then return false end
  local checked, accepted = pcall(function()
    local prototype = technology.prototype
    return technology.name == declaration.id and prototype ~= nil
      and prototype.max_level == INFINITE_MAX_LEVEL
      and exact_recipes(recipes, prototype.effects, change)
  end)
  return checked and accepted or false
end

return M
