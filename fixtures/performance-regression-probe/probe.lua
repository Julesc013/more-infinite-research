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
  local result = callback(...)
  local elapsed = math.max(0, now() - started)
  log("[MIR_PERFORMANCE_PHASE] end " .. phase .. " " .. tostring(current))
  local row = M.phases[phase]
  row.runs = row.runs + 1
  row.seconds = row.seconds + elapsed
  return result
end

return M
