local resolution = require("prototypes.mir.planner.effect_ownership.resolution")
local planned_operations = require("prototypes.mir.planner.effect_ownership.planned_operations")

local M = {}

M.resolve = resolution.resolve
M.resolve_operations = planned_operations.resolve

return M
