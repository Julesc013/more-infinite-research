local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_diff = require("prototypes.mir.graph.diff")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local scc_kernel = require("prototypes.mir.graph.scc")
local telemetry = require("prototypes.mir.report.compiler_telemetry")

local M = {}

local function sorted_prerequisites(technology)
  local prerequisites = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(prerequisites, prerequisite)
  end
  table.sort(prerequisites)
  return prerequisites
end

local function planned_technologies(plan)
  local out = {}
  for _, operation in ipairs((plan and plan.operations) or {}) do
    if operation.operation == "emit_stream" or operation.operation == "emit_base_extension" then
      out[operation.technology_name] = operation
    end
  end
  return out
end

-- Compatibility probe used by the bounded external-cycle fixture. It delegates
-- component semantics to the same SCC kernel used by planner qualification.
function M.inspect_reachable(root_name, options)
  options = options or {}
  local lookup = options.technology_lookup or data_raw.technology
  local is_generated = options.is_generated or generated_registry.contains
  local adjacency, technologies, queue, seen = {}, {}, {root_name}, {}
  local index = 1
  while index <= #queue do
    local name = queue[index]
    index = index + 1
    if not seen[name] then
      seen[name] = true
      local technology = lookup(name)
      if not technology then
        error("MIR generated technology graph references missing technology " .. tostring(name) .. ".", 2)
      end
      if technology.enabled == false then
        error("MIR generated technology graph references disabled technology " .. tostring(name) .. ".", 2)
      end
      technologies[name] = technology
      adjacency[name] = sorted_prerequisites(technology)
      for _, prerequisite in ipairs(adjacency[name]) do table.insert(queue, prerequisite) end
    end
  end

  local analysis = scc_kernel.analyze(adjacency)
  local external_cycle_count = 0
  for _, component in ipairs(analysis.components) do
    local cyclic = #component.nodes > 1
    if #component.nodes == 1 then
      for _, prerequisite in ipairs(adjacency[component.nodes[1]] or {}) do
        if prerequisite == component.nodes[1] then cyclic = true end
      end
    end
    if cyclic then
      local generated = false
      for _, name in ipairs(component.nodes) do if is_generated(name) then generated = true end end
      local witness = table.concat(component.nodes, " -> ") .. " -> " .. component.nodes[1]
      if generated then error("MIR generated technology prerequisite cycle: " .. witness .. ".", 2) end
      external_cycle_count = external_cycle_count + 1
      error("External technology prerequisite cycle reachable from MIR generated technology "
        .. tostring(root_name) .. ": " .. witness .. ". Factorio will reject this technology graph.", 2)
    end
  end
  local checked = 0
  for _ in pairs(technologies) do checked = checked + 1 end
  return {valid = true, root = root_name, checked_node_count = checked, external_cycle_count = external_cycle_count}
end

local function assert_equal(label, expected, actual)
  if expected ~= actual then
    error("MIR realized technology graph differs from the qualified virtual graph (" .. label
      .. "): expected " .. tostring(expected) .. ", actual " .. tostring(actual) .. ".", 3)
  end
end

local function same_names(left, right)
  if #left ~= #right then return false end
  for index = 1, #left do if left[index] ~= right[index] then return false end end
  return true
end

function M.assert_registered_technologies(plan)
  local expected = plan and plan.validation_summary and plan.validation_summary.technology_graph
  if not expected then error("MIR CompilationPlan lacks virtual technology-graph qualification evidence.", 2) end

  -- The virtual graph has already been fully qualified. Capture the realized
  -- graph from the Factorio prototype registry and prove exact node equality;
  -- equal graph input
  -- necessarily retains the qualified SCC, condensation, and proof results.
  local actual_technologies = data_raw.prototypes("technology")
  local actual_snapshot
  if graph_snapshot.matches_prototypes(expected.graph_snapshot, actual_technologies) then
    -- The normalized live projection is byte-for-byte equal to the already
    -- qualified snapshot. Reuse its exact authority and avoid a redundant
    -- full-graph canonicalization on the successful release path.
    actual_snapshot = expected.graph_snapshot
  else
    -- Preserve complete independently fingerprinted diagnostics whenever the
    -- live graph differs. The fast path never converts a mismatch into trust.
    actual_snapshot = graph_snapshot.new(actual_technologies)
  end
  local difference = graph_diff.compare(expected.graph_snapshot, actual_snapshot)
  if not difference.equal then
    error("MIR realized technology graph snapshot differs from its qualified virtual snapshot: "
      .. difference.diff_fingerprint .. ".", 2)
  end
  assert_equal("graph fingerprint", expected.graph_fingerprint, actual_snapshot.graph_fingerprint)

  local registered = generated_registry.sorted_names()
  local planned = planned_technologies(plan)
  local registered_set, parity = {}, {}
  for _, name in ipairs(registered) do
    registered_set[name] = true
    local technology = data_raw.technology(name)
    if not technology then error("MIR registered generated technology is missing: " .. name .. ".", 2) end
    if technology.enabled == false then error("MIR generated technology is disabled: " .. name .. ".", 2) end
    local operation = planned[name]
    if not operation then error("MIR emitted technology is absent from CompilationPlan: " .. name .. ".", 2) end
    local expected_prerequisites = sorted_prerequisites(operation.technology)
    local actual_prerequisites = sorted_prerequisites(technology)
    if not same_names(expected_prerequisites, actual_prerequisites) then
      error("MIR realized technology prerequisites differ for " .. name .. ".", 2)
    end
    local proof = expected.proofs[name]
    if not proof or proof.status ~= "passed" then
      error("MIR emitted technology lacks a realized passing graph proof: " .. name .. ".", 2)
    end
    table.insert(parity, {
      technology_name = name,
      prerequisites = actual_prerequisites,
      prerequisite_fingerprint = fingerprint.of(actual_prerequisites),
      enabled = true,
      component_id = expected.component_assignments[name],
      planner_proof = "passed",
      realized_proof = proof.status
    })
  end
  for name in pairs(planned) do
    if not registered_set[name] then error("CompilationPlan accepted technology was not emitted: " .. name .. ".", 2) end
  end

  local result = {
    schema = 2,
    valid = true,
    registered_technology_count = #registered,
    planned_technology_count = (function()
      local count = 0
      for _ in pairs(planned) do count = count + 1 end
      return count
    end)(),
    checked_node_count = #(actual_snapshot.nodes or {}),
    expected_graph_fingerprint = expected.graph_fingerprint,
    actual_graph_fingerprint = actual_snapshot.graph_fingerprint,
    component_assignment_fingerprint = expected.component_assignment_fingerprint,
    condensation_topology_fingerprint = expected.condensation_topology_fingerprint,
    proof_fingerprint = expected.proof_fingerprint,
    graph_diff_fingerprint = difference.diff_fingerprint,
    technologies = parity
  }
  result.parity_fingerprint = fingerprint.of(result)
  telemetry.count("technology_graph_parity_rows", #parity)
  return result
end

return M
