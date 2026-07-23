local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")
local technology_operation_executor = require("prototypes.mir.emit.technology_operation_executor")

local M = {}

function M.apply_plan(plan, journal, transformations_by_key)
  for _, operation in ipairs(plan or {}) do
    if operation.operation ~= "emit_base_extension" then
      error("Unsupported base continuation operation: " .. tostring(operation.operation), 2)
    end
    if data_raw.technology(operation.technology_name) then
      error("Base continuation output identity appeared after planning: " .. operation.technology_name, 2)
    end
    technology_operation_executor.apply_base_continuation(
      operation, journal, transformations_by_key and transformations_by_key[operation.key])
    diagnostics.extension(operation.diagnostics)
  end
end

return M
