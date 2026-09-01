local M = {}

local function assert_sink(sink)
  if not sink or type(sink.decision) ~= "function" then
    error("decision_export requires a sink with decision(row)", 3)
  end
end

function M.emit(sink, record)
  assert_sink(sink)
  sink.decision(record)
  return record
end

function M.emit_all(sink, records)
  local out = {}
  for _, record in ipairs(records or {}) do
    table.insert(out, M.emit(sink, record))
  end
  return out
end

return M
