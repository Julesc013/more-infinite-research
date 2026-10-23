-- Select the captured direct-effect profile before loading its binding body.
-- A K2SO data stage has a published spoilage-pack subset, so it cannot reuse
-- the Space Age mapping merely because both expose the named packs.
local M = {}

local K2SO_MODS = {"Krastorio2", "Krastorio2-spaced-out", "Krastorio2Assets", "k2so-assets"}

local function has_mod(active_mods, name)
  local version = active_mods[name]
  if version == nil then return false end
  if type(version) ~= "string" or version == "" then
    error("MIR scripted-effect binding has an invalid mod version for " .. name, 2)
  end
  return true
end

-- Only the exact four-marker K2SO profile has the recorded spoilage subset.
-- An active but partial overhaul selection fails closed. Asset archives on
-- their own do not activate the overhaul or invalidate ordinary Space Age.
function M.select(active_mods, raw)
  if type(active_mods) ~= "table" then
    error("MIR scripted-effect binding requires the data-stage mods table", 2)
  end
  local k2so = has_mod(active_mods, "Krastorio2") or has_mod(active_mods, "Krastorio2-spaced-out")
  if k2so then
    for index = 1, #K2SO_MODS do
      if not has_mod(active_mods, K2SO_MODS[index]) then
        error("MIR scripted-effect binding has an unsupported partial K2SO selection", 2)
      end
    end
  end
  if not has_mod(active_mods, "space-age") then
    error("MIR scripted-effect binding requires space-age", 2)
  end
  if k2so then
    return require("compatibility.space_age_scripted_effects.k2so").select(raw)
  end
  return require("compatibility.space_age_scripted_effects.space_age").select(raw)
end

return M
