local deepcopy = require("prototypes.mir.core.deepcopy")
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

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
local WITNESS_LIMIT = 64

local function state()
  return compiler_context.current():state_view("compiler_telemetry", function()
    local counters, phases = {}, {}
    for _, name in ipairs(REQUIRED_COUNTERS) do counters[name] = 0 end
    for _, name in ipairs(REQUIRED_PHASES) do phases[name] = {runs = 0, seconds = 0} end
    return {counters = counters, phases = phases, witnesses = {}}
  end)
end

local function now()
  if os and type(os.clock) == "function" then return os.clock() end
  return 0
end

function M.count(name, amount)
  local counters = state().counters
  counters[name] = (counters[name] or 0) + (amount or 1)
  return counters[name]
end

function M.observe_max(name, value)
  local counters = state().counters
  value = tonumber(value) or 0
  counters[name] = math.max(counters[name] or 0, value)
end

function M.start_phase(name)
  local phases = state().phases
  phases[name] = phases[name] or {runs = 0, seconds = 0}
  phases[name].started_at = now()
end

function M.finish_phase(name)
  local phases = state().phases
  local phase = phases[name] or {runs = 0, seconds = 0}
  phase.runs = phase.runs + 1
  if phase.started_at then phase.seconds = phase.seconds + math.max(0, now() - phase.started_at) end
  phase.started_at = nil
  phases[name] = phase
end

function M.witness(kind, value)
  local witnesses = state().witnesses
  witnesses[kind] = witnesses[kind] or {}
  if #witnesses[kind] < WITNESS_LIMIT then table.insert(witnesses[kind], tostring(value)) end
end

function M.snapshot()
  local current = state()
  return deepcopy({
    schema = 1,
    counters = current.counters,
    phases = current.phases,
    witnesses = current.witnesses,
    witness_limit = WITNESS_LIMIT
  })
end

return M
