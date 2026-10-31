-- Settings-stage adapter for the delivered historical direct technologies.
local target = require("platform.target")
local historical_settings = require("research.historical_direct_settings")

local M = {}

function M.apply()
  if target.reduced ~= true then error("MIR reduced settings adapter requires a reduced target", 2) end
  local stage = rawget(_G, "data")
  if type(stage) ~= "table" or type(stage.extend) ~= "function" then
    error("MIR reduced settings adapter requires data:extend", 2)
  end
  stage:extend(historical_settings.prototypes(target.id))
end

return M
