-- Relevant F200 ATAN identities shared by settings, data and runtime.
local M = {}

function M.select(active_mods, target)
  if type(active_mods) ~= "table" or target.id ~= "f200" or target.factorio_version ~= "2.0" then return nil end
  local air, ash = active_mods["atan-air-scrubbing"], active_mods["atan-ash"]
  -- A single ATAN marker never admitted either identity. Both named markers
  -- describe the published predecessor, however, so changed versions cannot
  -- silently remove its two saved technologies.
  if air == nil or ash == nil then return nil end
  if target.minimum_base ~= "2.0.77" then
    error("MIR unsupported F200 ATAN saved-profile transition: target minimum base changed", 2)
  end
  if air ~= "0.2.8" or ash ~= "2.2.1" then
    error("MIR unsupported F200 ATAN saved-profile transition: captured ATAN versions changed", 2)
  end
  if active_mods["space-age"] == nil then return "base" end
  if active_mods["space-age"] ~= "2.0.77" then
    error("MIR unsupported F200 ATAN saved-profile transition: captured Space Age version changed", 2)
  end
  return "space-age"
end

return M
