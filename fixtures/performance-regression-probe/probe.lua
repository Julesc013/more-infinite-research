local M = {
  schema = 1,
  phases = {
    snapshot = {runs = 0, seconds = 0},
    graph = {runs = 0, seconds = 0},
    planning = {runs = 0, seconds = 0},
    postconditions = {runs = 0, seconds = 0}
  }
}
local sequence = 0

local function now()
  if os and type(os.clock) == "function" then return os.clock() end
  return 0
end

function M.measure(phase, callback, ...)
  sequence = sequence + 1
  local current = sequence
  log("[MIR_PERFORMANCE_PHASE] start " .. phase .. " " .. tostring(current))
  local started = now()
  local arguments = table.pack(...)
  local results = table.pack(xpcall(function()
    return callback(table.unpack(arguments, 1, arguments.n))
  end, debug.traceback))
  local elapsed = math.max(0, now() - started)
  log("[MIR_PERFORMANCE_PHASE] end " .. phase .. " " .. tostring(current))
  local row = M.phases[phase]
  row.runs = row.runs + 1
  row.seconds = row.seconds + elapsed
  if not results[1] then error(results[2], 2) end
  return table.unpack(results, 2, results.n)
end

return M
