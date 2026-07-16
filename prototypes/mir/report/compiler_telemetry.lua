local deepcopy = require("prototypes.mir.core.deepcopy")

local M = {}
local REQUIRED_COUNTERS = {
  "recipes",
  "technologies",
  "effects",
  "graph_edges",
  "graph_components",
  "cyclic_components",
  "recipe_index_scans",
  "recipe_fact_copies",
  "candidate_operations",
  "accepted_operations",
  "rejected_operations",
  "diagnostic_rows"
}
local REQUIRED_PHASES = {"snapshot", "graph", "planning", "postconditions"}
local counters = {}
local phases = {}
local witnesses = {}
local WITNESS_LIMIT = 64

for _, name in ipairs(REQUIRED_COUNTERS) do counters[name] = 0 end
for _, name in ipairs(REQUIRED_PHASES) do phases[name] = {runs = 0, seconds = 0} end

local function now()
  if os and type(os.clock) == "function" then return os.clock() end
  return 0
end

function M.count(name, amount)
  counters[name] = (counters[name] or 0) + (amount or 1)
  return counters[name]
end

function M.observe_max(name, value)
  value = tonumber(value) or 0
  counters[name] = math.max(counters[name] or 0, value)
end

function M.start_phase(name)
  phases[name] = phases[name] or {runs = 0, seconds = 0}
  phases[name].started_at = now()
end

function M.finish_phase(name)
  local phase = phases[name] or {runs = 0, seconds = 0}
  phase.runs = phase.runs + 1
  if phase.started_at then phase.seconds = phase.seconds + math.max(0, now() - phase.started_at) end
  phase.started_at = nil
  phases[name] = phase
end

function M.witness(kind, value)
  witnesses[kind] = witnesses[kind] or {}
  if #witnesses[kind] < WITNESS_LIMIT then table.insert(witnesses[kind], tostring(value)) end
end

function M.snapshot()
  return deepcopy({
    schema = 1,
    counters = counters,
    phases = phases,
    witnesses = witnesses,
    witness_limit = WITNESS_LIMIT
  })
end

return M
