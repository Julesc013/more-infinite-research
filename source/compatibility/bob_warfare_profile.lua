-- Narrow F200 Base binding for the captured Bob Warfare armor component.
-- Archive pins are evidence, not an activation fingerprint.
local target = require("platform.target")

local M = {}

function M.applies(active)
  if type(active) ~= "table" or active.bobwarfare == nil then return false end
  if target.id ~= "f200" or target.factorio_version ~= "2.0" then return false end
  if active["space-age"] ~= nil then
    error("MIR unsupported F200 Bob Warfare saved-profile transition: Space Age changes the captured armor binding", 2)
  end
  if active.Krastorio2 ~= nil or active.Krastorio2Assets ~= nil
      or active["Krastorio2-spaced-out"] ~= nil or active["k2so-assets"] ~= nil then
    error("MIR unsupported F200 Bob Warfare saved-profile transition: Krastorio changes the captured armor binding", 2)
  end
  return true
end

return M
