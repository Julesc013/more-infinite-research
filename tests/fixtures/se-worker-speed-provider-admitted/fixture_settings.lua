local M = {}

local CAP = "mir-max-level-worker-robots-speed"
local CAPS = {source = 0, admission = 0, old = 10, candidate = 10}

function M.apply(stage)
  local cap = CAPS[stage]
  if cap == nil then error("[se-worker-speed-provider] unknown settings stage") end
  local setting = data.raw["int-setting"] and data.raw["int-setting"][CAP]
  if type(setting) ~= "table" then error("[se-worker-speed-provider] worker-speed cap setting is absent") end
  if setting.minimum_value ~= nil and setting.minimum_value > cap then
    error("[se-worker-speed-provider] worker-speed cap rejects fixture stage")
  end
  setting.default_value = cap
end

return M
