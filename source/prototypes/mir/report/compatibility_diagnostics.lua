local decision_export = require("prototypes.mir.report.decision_export")

local M = {}

local function assert_sink(sink, method)
  if not sink or type(sink[method]) ~= "function" then
    error("compatibility diagnostics report sink missing method: " .. method, 3)
  end
end

function M.decision(sink, row)
  return decision_export.emit(sink, row)
end

function M.loop_risk(sink, row)
  assert_sink(sink, "loop_risk")
  sink.loop_risk(row)
  return row
end

function M.compatibility_plan(sink, row)
  assert_sink(sink, "compatibility_plan")
  sink.compatibility_plan(row)
  return row
end

return M
