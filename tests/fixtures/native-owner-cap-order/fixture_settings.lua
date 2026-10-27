-- Shared startup-setting stage for the disposable F210 native-owner cap-order
-- fixture. The three package versions select only their intended cap.
local M = {}

local CAPS = {canonical = 1, permuted = 1, relaxed = 0}

function M.apply(stage)
  local cap = CAPS[stage]
  if cap == nil then error("[mir5-native-owner-cap-order] unknown settings stage: " .. tostring(stage)) end
  local settings = data.raw["int-setting"]
  local row = settings and settings["ips-max-level-research_steel"]
  if type(row) ~= "table" then error("[mir5-native-owner-cap-order] steel cap setting is absent") end
  if row.minimum_value ~= nil and row.minimum_value > cap then
    error("[mir5-native-owner-cap-order] steel cap setting rejects stage value")
  end
  row.default_value = cap
end

return M
