local M = {}

local CAP = "mir-max-level-worker-robots-speed"
local CAPS = {source15 = 0, ["old-negative15"] = 10, successor16 = 10}

function M.apply(stage)
  local cap = CAPS[stage]
  if cap == nil then error("[mir5-worker-speed-cap-ten] unknown settings stage: " .. tostring(stage)) end
  local row = data.raw["int-setting"] and data.raw["int-setting"][CAP]
  if type(row) ~= "table" then error("[mir5-worker-speed-cap-ten] worker-speed cap setting is absent") end
  if row.minimum_value ~= nil and row.minimum_value > cap then
    error("[mir5-worker-speed-cap-ten] worker-speed cap setting rejects stage value")
  end
  -- This fixture changes only its selected startup default. It does not
  -- create, rename, or otherwise alter a player setting identity.
  row.default_value = cap
end

return M
