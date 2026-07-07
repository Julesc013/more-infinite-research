local C = require("prototypes.mir.streams.registry")
local costs = require("prototypes.mir.planner.costs")

local function apply_max_level(key, spec)
  local tech_name = "recipe-prod-" .. key .. "-1"
  local tech = (data.raw.technology or {})[tech_name]
  if not tech then return end

  local max_level = costs.max_level_for(key, spec)
  if max_level == "infinite" then
    tech.max_level = "infinite"
  else
    tech.max_level = max_level
  end
end

for key, spec in pairs(C.streams) do
  apply_max_level(key, spec)
end
