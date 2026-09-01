local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local generated_registry = require("prototypes.mir.domain.facts.generated_technology_registry")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_diff = require("prototypes.mir.graph.diff")
local graph_qualification = require("prototypes.mir.graph.qualification")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local scc_kernel = require("prototypes.mir.graph.scc")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local technology_replacement = require("prototypes.mir.emit.technology_replacement")

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

function M.assert_registered_technologies(plan, replacement_journal)
  local expected = plan and plan.validation_summary and plan.validation_summary.technology_graph
  if not expected then error("MIR CompilationPlan lacks virtual technology-graph qualification evidence.", 2) end
  replacement_journal = replacement_journal or technology_replacement.new_journal()
  local replacement_summary = technology_replacement.validate_journal(replacement_journal)

  -- The virtual graph has already been fully qualified. Capture the realized
  -- graph from the Factorio prototype registry and prove exact node equality;
  -- equal graph input
  -- necessarily retains the qualified SCC, condensation, and proof results.
  local actual_technologies = data_raw.prototypes("technology")
  local actual_snapshot
  local comparison_snapshot = expected.graph_snapshot
  local realized_authority = expected
  local graph_requalified = false
  if graph_snapshot.matches_prototypes(expected.graph_snapshot, actual_technologies) then
    -- The normalized live projection is byte-for-byte equal to the already
    -- qualified snapshot. Reuse its exact authority and avoid a redundant
    -- full-graph canonicalization on the successful release path.
    actual_snapshot = expected.graph_snapshot
    if replacement_summary.entry_count > 0 then
      error("MIR technology replacement journal contains entries but the realized graph did not change.", 2)
    end
  else
    -- Preserve complete independently fingerprinted diagnostics whenever the
    -- live graph differs. The fast path never converts a mismatch into trust.
    actual_snapshot = graph_snapshot.new(actual_technologies)
    if replacement_summary.entry_count == 0 then
      local unexpected = graph_diff.compare(expected.graph_snapshot, actual_snapshot)
      error("MIR realized technology graph snapshot differs from its qualified virtual snapshot: "
        .. unexpected.diff_fingerprint .. ".", 2)
    end
    comparison_snapshot = graph_snapshot.apply_replacement_journal(
      expected.graph_snapshot, replacement_journal.entries)
    local projected_difference = graph_diff.compare(comparison_snapshot, actual_snapshot)
    if not projected_difference.equal then
      error("MIR realized technology graph differs from its exact replacement-journal projection: "
        .. projected_difference.diff_fingerprint .. ".", 2)
    end
    realized_authority = graph_qualification.validate_operations(plan.operations, {actual = true})
    if realized_authority.rejected_planned_technology_count ~= 0
      or realized_authority.accepted_planned_technology_count ~= realized_authority.planned_technology_count then
      error("MIR realized replacement graph failed fresh graph qualification.", 2)
    end
    local qualification_difference = graph_diff.compare(
      realized_authority.graph_snapshot, actual_snapshot)
    if not qualification_difference.equal then
      error("MIR realized graph changed during replacement requalification: "
        .. qualification_difference.diff_fingerprint .. ".", 2)
    end
    graph_requalified = true
  end
  local difference = graph_diff.compare(comparison_snapshot, actual_snapshot)
  if not difference.equal then
    error("MIR realized technology graph snapshot differs from its qualified virtual snapshot: "
      .. difference.diff_fingerprint .. ".", 2)
  end
  assert_equal("graph fingerprint", comparison_snapshot.graph_fingerprint, actual_snapshot.graph_fingerprint)

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
    local realized_node = graph_snapshot.technology_view(realized_authority.graph_snapshot)[name]
    if not realized_node then error("MIR realized graph qualification omitted " .. name .. ".", 2) end
    local expected_prerequisites = realized_node.prerequisites or {}
    local actual_prerequisites = sorted_prerequisites(technology)
    if not same_names(expected_prerequisites, actual_prerequisites) then
      error("MIR realized technology prerequisites differ for " .. name .. ".", 2)
    end
    local proof = realized_authority.proofs[name]
    if not proof or proof.status ~= "passed" then
      error("MIR emitted technology lacks a realized passing graph proof: " .. name .. ".", 2)
    end
    table.insert(parity, {
      technology_name = name,
      prerequisites = actual_prerequisites,
      prerequisite_fingerprint = fingerprint.of(actual_prerequisites),
      enabled = true,
      component_id = realized_authority.component_assignments[name],
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
    planning_graph_fingerprint = expected.graph_fingerprint,
    expected_graph_fingerprint = comparison_snapshot.graph_fingerprint,
    actual_graph_fingerprint = actual_snapshot.graph_fingerprint,
    component_assignment_fingerprint = realized_authority.component_assignment_fingerprint,
    condensation_topology_fingerprint = realized_authority.condensation_topology_fingerprint,
    proof_fingerprint = realized_authority.proof_fingerprint,
    graph_diff_fingerprint = difference.diff_fingerprint,
    replacement_journal_fingerprint = replacement_summary.journal_fingerprint,
    replacement_count = replacement_summary.entry_count,
    replacement_graph_requalified = graph_requalified,
    technologies = parity
  }
  result.parity_fingerprint = fingerprint.of(result)
  telemetry.count("technology_graph_parity_rows", #parity)
  return result
end

return M
