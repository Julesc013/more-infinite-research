-- Final-fixes adapter for a target's delivered historical direct technologies.
local target = require("platform.target")
local generator = require("research.generator")
local historical_direct = require("research.historical_direct")
local historical_settings = require("research.historical_direct_settings")

local M = {}

function M.apply()
  if target.reduced ~= true then error("MIR reduced final-fixes adapter requires a reduced target", 2) end
  local stage = rawget(_G, "data")
  if type(stage) ~= "table" or type(stage.extend) ~= "function" then
    error("MIR reduced final-fixes adapter requires data:extend", 2)
  end
  local current_settings = rawget(_G, "settings")
  local startup = type(current_settings) == "table" and current_settings.startup or nil
  local values = historical_settings.resolve(target.id, startup)
  generator.install(historical_direct.technologies(target.id, values, stage.raw), stage)
end

return M
