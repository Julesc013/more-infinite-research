-- This selector must stay independent of the full stream/settings catalogue.
-- Prototype stages can choose the bounded compiler before loading its opponent.
local M = {name = "mir-compiler-profile"}

function M.get(factorio_line)
  -- Historical packages retain their numeric-unit and reduced-surface path.
  -- They do not share the modern startup/profile contract.
  if type(factorio_line) == "string" and factorio_line:match("^0%.") then return "full" end
  local setting = settings and settings.startup and settings.startup[M.name]
  -- Existing factories must keep the broad catalogue unless the player
  -- explicitly selects the reduced profile before loading.
  local value = setting and setting.value or "full"
  if value ~= "classic" and value ~= "full" then
    error("Unsupported MIR compiler profile: " .. tostring(value), 2)
  end
  return value
end

function M.prototype()
  return {
    type = "string-setting",
    name = M.name,
    setting_type = "startup",
    default_value = "full",
    allowed_values = {"classic", "full"},
    order = "a-000-compiler-profile",
    localised_name = {"mod-setting-name.mir-compiler-profile"},
    localised_description = {"mod-setting-description.mir-compiler-profile"}
  }
end

return M
