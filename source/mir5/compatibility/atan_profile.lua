-- Relevant F200 ATAN identities shared by settings, data and runtime.
local M = {}

function M.select(active_mods, target)
  if type(active_mods) ~= "table" or target.id ~= "f200" or target.factorio_version ~= "2.0"
    or target.minimum_base ~= "2.0.77" or active_mods["atan-air-scrubbing"] ~= "0.2.8"
    or active_mods["atan-ash"] ~= "2.2.1" then return nil end
  if active_mods["space-age"] == nil then return "base" end
  if active_mods["space-age"] == "2.0.77" then return "space-age" end
  return nil
end

return M
