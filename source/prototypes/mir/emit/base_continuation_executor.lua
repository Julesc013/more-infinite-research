local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local technology_operation_executor = require("prototypes.mir.emit.technology_operation_executor")

local M = {}

function M.apply_plan(plan, transformation_plan, journal)
  for _, operation in ipairs(plan or {}) do
    if operation.operation ~= "emit_base_extension" then
      error("Unsupported base continuation operation: " .. tostring(operation.operation), 2)
    end
    diagnostics.extension(operation.diagnostics)
  end
  return technology_operation_executor.apply_plan(
    transformation_plan, journal, {kind = "base-continuation"})
end

return M
