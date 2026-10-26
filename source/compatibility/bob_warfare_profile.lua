-- Captured modern Bob Warfare armor component and native laser binding.
-- Archive pins are evidence, not an activation fingerprint.
local target = require("platform.target")

local M = {}

function M.applies(active)
  if type(active) ~= "table" or active.bobwarfare == nil then return false end
  local f200 = target.id == "f200" and target.factorio_version == "2.0"
  local f210 = target.id == "f210" and target.factorio_version == "2.1"
  if not f200 and not f210 then return false end
  if f200 and active["space-age"] ~= nil then
    error("MIR unsupported F200 Bob Warfare saved-profile transition: Space Age changes the captured armor binding", 2)
  end
  if active.Krastorio2 ~= nil or active.Krastorio2Assets ~= nil
      or active["Krastorio2-spaced-out"] ~= nil or active["k2so-assets"] ~= nil then
    error("MIR unsupported " .. target.id:upper() .. " Bob Warfare saved-profile transition: Krastorio changes the captured armor binding", 2)
  end
  return true
end

return M
