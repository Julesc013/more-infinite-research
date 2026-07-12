local deepcopy = require("prototypes.mir.core.deepcopy")
local base_extensions = require("prototypes.mir.emit.base_extensions")
local stream_compiler = require("prototypes.mir.planner.stream_compiler")

local M = {}
local latest = nil

function M.compile()
  if latest then return latest end
  local stream_plan = stream_compiler.compile()
  local base_plan = base_extensions.plan_all()
  latest = {
    schema = 1,
    stream_plan = stream_plan,
    base_extension_operations = base_plan
  }
  stream_compiler.accept(stream_plan)
  return latest
end

function M.apply_streams()
  local plan = M.compile()
  stream_compiler.apply(plan.stream_plan)
end

function M.apply_base_extensions()
  local plan = M.compile()
  base_extensions.apply_plan(plan.base_extension_operations)
end

function M.snapshot()
  local plan = M.compile()
  return {
    schema = plan.schema,
    stream_plan = plan.stream_plan:artifact(),
    base_extension_operations = deepcopy(plan.base_extension_operations)
  }
end

return M
