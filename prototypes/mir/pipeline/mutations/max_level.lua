local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local policy = require("prototypes.mir.policy.max_level")

local M = {}

function M.apply()
  for _, command in ipairs(policy.plan()) do
    local technology = data_raw.technology(command.technology)
    if technology then technology.max_level = command.max_level end
  end
end

return M
