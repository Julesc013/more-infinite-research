-- Compatibility facade retained for downstream integrations. Planning and
-- mutation authority are separate in C9.
local planner = require("prototypes.mir.planner.base_continuations")
local executor = require("prototypes.mir.emit.base_continuation_executor")

local M = {}
M.plan_all = planner.plan_all
M.apply_plan = executor.apply_plan

function M.emit_all()
  executor.apply_plan(planner.plan_all())
  return M
end

return M
