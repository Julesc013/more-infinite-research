local function fail(message)
  error("MIR synthetic scale validation failed: " .. message)
end

local compilation_plan = require("__more-infinite-research__.prototypes.mir.planner.compilation_plan")
local technology_graph = require("__more-infinite-research__.prototypes.mir.planner.technology_graph")
local fingerprint = require("__more-infinite-research__.prototypes.mir.core.fingerprint")
local generation_plan = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-generation-plan"]

local prototype = data.raw["mod-data"] and data.raw["mod-data"]["more-infinite-research-coverage-report"]
local summary = prototype and prototype.data and prototype.data.summary
if not summary then fail("coverage summary is missing") end

local minimums = {
  total_recipes = 1000,
  accounted_recipes = 1000,
  candidate_count = 1000,
  technology_count = 60000,
  technology_effect_count = 60000,
  graph_edge_count = 60000
}
for field, minimum in pairs(minimums) do
  if (tonumber(summary[field]) or 0) < minimum then
    fail(field .. " expected at least " .. minimum .. ", got " .. tostring(summary[field]))
  end
end
if summary.accounted_recipes ~= summary.total_recipes then fail("recipe accounting is incomplete") end
if summary.dangling_effects ~= 0 then fail("dangling recipe effects were found") end
if summary.duplicate_owners ~= 0 then fail("duplicate recipe owners were found") end
if summary.recipe_fact_scan_count ~= 1 then fail("recipe facts were rebuilt") end
if summary.technology_scan_count ~= 1 then fail("technology coverage scan count changed") end

local plan = compilation_plan.snapshot()
local telemetry = plan and plan.telemetry
if not telemetry or telemetry.counters.technologies < 60000
  or telemetry.counters.effects < 60000
  or telemetry.counters.graph_edges < 60000 then
  fail("compiler telemetry did not observe the maximum-legal materialized graph campaign")
end
if telemetry.counters.cyclic_components ~= 0 then
  fail("materialized Factorio graph must remain acyclic")
end
if not generation_plan or not generation_plan.data or type(generation_plan.data.plan_fingerprint) ~= "string" then
  fail("generation plan fingerprint is missing")
end

local STRESS_TOTAL = 100000
local STRESS_LARGE_SCC = 25000
local STRESS_SMALL_SCC_END = 30000
local STRESS_SMALL_SCC_SIZE = 5
local random_order = mods and mods["mir-fixture-synthetic-scale-random-order"] ~= nil

local function stress_index(position)
  if not random_order then return position end
  return ((position * 7919 + 4729) % STRESS_TOTAL) + 1
end

local function stress_prerequisite(index)
  if index <= STRESS_LARGE_SCC then
    return index == STRESS_LARGE_SCC and 1 or index + 1
  end
  if index <= STRESS_SMALL_SCC_END then
    local offset = (index - STRESS_LARGE_SCC - 1) % STRESS_SMALL_SCC_SIZE
    return offset == STRESS_SMALL_SCC_SIZE - 1 and index - STRESS_SMALL_SCC_SIZE + 1 or index + 1
  end
  return index - 1
end

local stress_operations = {}
for position = 1, STRESS_TOTAL do
  local index = stress_index(position)
  local name = string.format("mir-synthetic-technology-%06d", index)
  table.insert(stress_operations, {
    operation = "emit_base_extension",
    key = name,
    technology_name = name,
    technology = {
      name = name,
      effects = {{type = "nothing"}},
      prerequisites = {string.format("mir-synthetic-technology-%06d", stress_prerequisite(index))},
      unit = {ingredients = {{"automation-science-pack", 1}}, count_formula = "1", time = 1},
      max_level = "infinite"
    }
  })
end

local stress = technology_graph.validate_operations(stress_operations)
if stress.node_count < STRESS_TOTAL or stress.edge_count < STRESS_TOTAL
  or stress.cyclic_component_count < 1001
  or stress.rejected_planned_technology_count ~= STRESS_TOTAL then
  fail("in-memory compiler graph did not cover 100000 technologies, effects, and edges")
end
local stress_components, large_component = {}
for _, component in ipairs(stress.cyclic_components or {}) do
  if #component.member_sample > 64 or #component.actual_cycle_witness > 64 then
    fail("SCC diagnostics exceeded the bounded 64-node witness budget")
  end
  if component.node_count == STRESS_LARGE_SCC then large_component = component end
  table.insert(stress_components, {
    component_member_id = component.component_member_id,
    component_topology_fingerprint = component.component_topology_fingerprint,
    internal_edge_count = component.internal_edge_count,
    node_count = component.node_count,
    classification = component.classification,
    member_sample = component.member_sample,
    actual_cycle_witness = component.actual_cycle_witness,
    actual_cycle_witness_truncated = component.actual_cycle_witness_truncated
  })
end
if not large_component or not large_component.nodes_truncated
  or not large_component.actual_cycle_witness_truncated then
  fail("25000-node in-memory SCC did not publish bounded diagnostics")
end
local stress_fingerprint = fingerprint.of({
  node_count = stress.node_count,
  edge_count = stress.edge_count,
  component_count = stress.component_count,
  cyclic_component_count = stress.cyclic_component_count,
  rejected_planned_technology_count = stress.rejected_planned_technology_count,
  cyclic_components = stress_components
})
log("[mir-fixture] synthetic-graph fingerprints coverage=" .. tostring(prototype.data.fingerprint)
  .. " generation=" .. tostring(generation_plan.data.plan_fingerprint)
  .. " compilation=" .. tostring(plan.semantic_fingerprint)
  .. " in_memory=" .. tostring(stress_fingerprint))
