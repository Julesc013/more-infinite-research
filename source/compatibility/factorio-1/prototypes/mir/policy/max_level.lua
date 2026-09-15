local C = require("prototypes.mir.streams.registry")
local costs = require("prototypes.mir.planner.costs")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

local M = {}

local function plan_max_level(key, spec)
  local tech_name = "recipe-prod-" .. key .. "-1"
  local tech = data_raw.technology(tech_name)
  if not tech then return end

  local max_level = costs.max_level_for(key, spec)
  return {technology = tech_name, max_level = max_level}
end

function M.plan()
  local commands = {}
  for key, spec in pairs(C.snapshot()) do
    local command = plan_max_level(key, spec)
    if command then table.insert(commands, command) end
  end
  table.sort(commands, function(a, b) return a.technology < b.technology end)
  return commands
end

return M
