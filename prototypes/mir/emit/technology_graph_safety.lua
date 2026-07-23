local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_diff = require("prototypes.mir.graph.diff")
local graph_qualification = require("prototypes.mir.graph.qualification")
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

function M.assert_registered_technologies(plan)
  local expected = plan and plan.validation_summary and plan.validation_summary.technology_graph
  if not expected then error("MIR CompilationPlan lacks virtual technology-graph qualification evidence.", 2) end

  local actual = graph_qualification.validate_operations(plan.operations, {actual = true})
  local difference = graph_diff.compare(expected.graph_snapshot, actual.graph_snapshot)
  if not difference.equal then
    error("MIR realized technology graph snapshot differs from its qualified virtual snapshot: "
      .. difference.diff_fingerprint .. ".", 2)
  end
  assert_equal("graph fingerprint", expected.graph_fingerprint, actual.graph_fingerprint)
  assert_equal("component assignments", expected.component_assignment_fingerprint,
    actual.component_assignment_fingerprint)
  assert_equal("condensation topology", expected.condensation_topology_fingerprint,
    actual.condensation_topology_fingerprint)
  assert_equal("graph proof", expected.proof_fingerprint, actual.proof_fingerprint)

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
    assert_equal("prerequisites for " .. name, fingerprint.of(expected_prerequisites),
      fingerprint.of(actual_prerequisites))
    local proof = actual.proofs[name]
    if not proof or proof.status ~= "passed" then
      error("MIR emitted technology lacks a realized passing graph proof: " .. name .. ".", 2)
    end
    table.insert(parity, {
      technology_name = name,
      prerequisites = actual_prerequisites,
      prerequisite_fingerprint = fingerprint.of(actual_prerequisites),
      enabled = true,
      component_id = actual.component_assignments[name],
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
    checked_node_count = actual.node_count,
    expected_graph_fingerprint = expected.graph_fingerprint,
    actual_graph_fingerprint = actual.graph_fingerprint,
    component_assignment_fingerprint = actual.component_assignment_fingerprint,
    condensation_topology_fingerprint = actual.condensation_topology_fingerprint,
    proof_fingerprint = actual.proof_fingerprint,
    graph_diff_fingerprint = difference.diff_fingerprint,
    technologies = parity
  }
  result.parity_fingerprint = fingerprint.of(result)
  telemetry.count("technology_graph_parity_rows", #parity)
  return result
end

return M
