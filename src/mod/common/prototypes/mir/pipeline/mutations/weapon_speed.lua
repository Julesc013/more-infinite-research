local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local policy = require("prototypes.mir.policy.weapon_speed")

local M = {}

function M.apply()
  for _, command in ipairs(policy.plan()) do
    local technology = data_raw.technology(command.technology)
    if technology then technology.effects = command.effects end
  end
end

return M
