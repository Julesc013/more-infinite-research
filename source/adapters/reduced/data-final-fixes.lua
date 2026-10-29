-- Final-fixes adapter for a target's delivered historical direct technologies.
local target = require("platform.target")
local generator = require("research.generator")
local historical_direct = require("research.historical_direct")
local historical_continuations = require("research.historical_continuations")
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
  local technologies = historical_direct.technologies(target.id, values, stage.raw)
  local continuations = historical_continuations.technologies(target.id, values, stage.raw)
  for index = 1, #continuations do technologies[#technologies + 1] = continuations[index] end
  require("research.science").apply_family(technologies, nil, {
    options=values.options, raw=stage.raw, target=target, mods=rawget(_G, "mods"), log=rawget(_G, "log"),
  })
  generator.install(technologies, stage)
end

return M
