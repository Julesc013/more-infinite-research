-- Select an approved gear profile before importing its exact recipe mapping.
-- An inactive profile never constructs its mapping table or preflights recipes.
local M = {}

local K2SO_MODS = {"Krastorio2", "Krastorio2-spaced-out", "Krastorio2Assets", "k2so-assets"}
local modern_catalogue = require("compatibility.modern_catalogue")

local function has_mod(mods, name)
  local version = mods[name]
  if version == nil then return false end
  if type(version) ~= "string" or version == "" then
    error("MIR gear binding has an invalid mod version for " .. name, 2)
  end
  return true
end

local function checked_copy(binding, raw)
  if type(raw) ~= "table" or type(raw.recipe) ~= "table" then
    error("MIR gear binding requires data.raw.recipe", 2)
  end
  local recipes = {}
  for index = 1, #binding.recipes do
    local name = binding.recipes[index]
    if type(raw.recipe[name]) ~= "table" then
      error("MIR gear binding missing required recipe " .. name, 2)
    end
    recipes[index] = name
  end
  if binding.preflight ~= nil then
    if type(binding.preflight) ~= "function" then error("MIR gear binding has an invalid native preflight", 2) end
    binding.preflight(raw)
  end
  return {profile = binding.profile, icon = binding.icon, recipes = recipes}
end

-- Select only exact approved profile markers. A partial K2SO selection has no
-- safe fallback to the one- or two-recipe mappings.
function M.select(mods, raw)
  if type(mods) ~= "table" then error("MIR gear binding requires the data-stage mods table", 2) end
  local space_age = has_mod(mods, "space-age")
  if modern_catalogue.is_k2_base(mods) then
    -- The shared predicate owns admission; retain binding's version-shape
    -- validation before importing the named K2 Base mapping.
    has_mod(mods, "Krastorio2")
    has_mod(mods, "Krastorio2Assets")
    return checked_copy(require("compatibility.gear_bindings.k2_base"), raw)
  end
  local k2so = false
  for index = 1, #K2SO_MODS do
    local present = has_mod(mods, K2SO_MODS[index])
    if index == 1 then k2so = present elseif present ~= k2so then
      error("MIR gear binding has an unsupported partial K2SO selection", 2)
    end
  end
  if k2so then
    if not space_age then
      error("MIR gear binding has an unsupported partial K2SO selection", 2)
    end
    return checked_copy(require("compatibility.gear_bindings.k2so"), raw)
  end
  if space_age then
    return checked_copy(require("compatibility.gear_bindings.space_age"), raw)
  end
  return checked_copy(require("compatibility.gear_bindings.vanilla"), raw)
end

return M
