-- Relevant F200 ATAN identities shared by settings, data and runtime.
local M = {}

function M.select(active_mods, target)
  if type(active_mods) ~= "table" or target.id ~= "f200" or target.factorio_version ~= "2.0" then return nil end
  local air, ash = active_mods["atan-air-scrubbing"], active_mods["atan-ash"]
  -- Both named providers select the variant. Mandatory data-stage checks
  -- validate its recipes, owners and presentation before any MIR publication;
  -- captured version strings remain evidence rather than a production gate.
  if air == nil or ash == nil then return nil end
  if target.minimum_base ~= "2.0.77" then
    error("MIR unsupported F200 ATAN saved-profile transition: target minimum base changed", 2)
  end
  if active_mods["space-age"] == nil then return "base" end
  return "space-age"
end

return M
