local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")
local gate_contract = require("prototypes.mir.domain.technology.gate")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local scc_kernel = require("prototypes.mir.graph.scc")
local condensation = require("prototypes.mir.graph.condensation")
local researchability = require("prototypes.mir.graph.researchability")
local graph_evidence = require("prototypes.mir.graph.evidence")

local M = {}
local WITNESS_NODE_LIMIT = 64
local CONTRIBUTING_SAMPLE_LIMIT = 16
local REJECTION_PRIORITY = {
  prerequisite_missing = 10,
  prerequisite_disabled = 20,
  prerequisite_mir_cycle = 30,
  prerequisite_mixed_cycle = 40,
  prerequisite_external_cycle = 50,
  effect_target_missing = 60,
  research_mechanism_missing = 70,
  research_lab_unavailable = 80,
  research_science_unreachable = 90
}

local function sorted_keys(values)
  local out = {}
  for key, _ in pairs(values or {}) do table.insert(out, key) end
  table.sort(out)
  return out
end

local function sorted_prerequisites(technology)
  local out = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(out, prerequisite)
  end
  table.sort(out)
  return out
end

local function planned_technologies(operations)
  local out = {}
  for _, operation in ipairs(operations or {}) do
    if (operation.operation == "emit_stream" or operation.operation == "emit_base_extension")
      and operation.technology then
      out[operation.technology_name] = operation.technology
    end
  end
  return out
end

local function build_graph(operations, options)
  options = options or {}
  local planned = planned_technologies(operations)
  local technologies = {}
  for name, technology in pairs(data_raw.prototypes("technology")) do technologies[name] = technology end
  if not options.actual then
    for name, technology in pairs(planned) do technologies[name] = technology end
  end

  local adjacency, reverse, edge_count, effect_count = {}, {}, 0, 0
  for _, name in ipairs(sorted_keys(technologies)) do
    adjacency[name] = sorted_prerequisites(technologies[name])
    reverse[name] = reverse[name] or {}
    effect_count = effect_count + #((technologies[name] and technologies[name].effects) or {})
    for _, prerequisite in ipairs(adjacency[name]) do
      edge_count = edge_count + 1
      reverse[prerequisite] = reverse[prerequisite] or {}
      table.insert(reverse[prerequisite], name)
    end
  end
  for _, values in pairs(reverse) do table.sort(values) end
  return technologies, planned, adjacency, reverse, edge_count, effect_count, graph_snapshot.new(technologies)
end

local function component_is_cycle(component, adjacency)
  if #component > 1 then return true end
  local name = component[1]
  for _, prerequisite in ipairs(adjacency[name] or {}) do
    if prerequisite == name then return true end
  end
  return false
end

local function bounded_component_nodes(component)
  local out = {}
  for index = 1, math.min(#component, WITNESS_NODE_LIMIT) do
    table.insert(out, component[index])
  end
  return out
end

local function component_internal_edges(component, adjacency)
  local members, edges = {}, {}
  for _, name in ipairs(component) do members[name] = true end
  for _, owner in ipairs(component) do
    for _, prerequisite in ipairs(adjacency[owner] or {}) do
      if members[prerequisite] then table.insert(edges, owner .. "\0" .. prerequisite) end
    end
  end
  table.sort(edges)
  return edges
end

local function find_actual_cycle(component, adjacency, maximum_nodes)
  local component_set, state, parent = {}, {}, {}
  for _, name in ipairs(component) do component_set[name] = true end

  for _, root in ipairs(component) do
    if not state[root] then
      state[root] = "visiting"
      local stack = {{name = root, next_index = 1}}
      while #stack > 0 do
        local frame = stack[#stack]
        local edges = adjacency[frame.name] or {}
        local next_name
        while frame.next_index <= #edges and not next_name do
          local candidate = edges[frame.next_index]
          frame.next_index = frame.next_index + 1
          if component_set[candidate] then next_name = candidate end
        end
        if not next_name then
          state[frame.name] = "complete"
          table.remove(stack)
        elseif not state[next_name] then
          parent[next_name] = frame.name
          state[next_name] = "visiting"
          table.insert(stack, {name = next_name, next_index = 1})
        elseif state[next_name] == "visiting" then
          local reverse_path, cursor = {}, frame.name
          while cursor and cursor ~= next_name do
            table.insert(reverse_path, cursor)
            cursor = parent[cursor]
          end
          if cursor == next_name then
            local path = {next_name}
            for index = #reverse_path, 1, -1 do table.insert(path, reverse_path[index]) end
            table.insert(path, next_name)
            local bounded = {}
            for index = 1, math.min(#path, maximum_nodes) do table.insert(bounded, path[index]) end
            return bounded, #path > maximum_nodes
          end
        end
      end
    end
  end
  return {}, false
end

local function cycle_class(component, planned)
  local planned_count = 0
  for _, name in ipairs(component) do
    if planned[name] then planned_count = planned_count + 1 end
  end
  if planned_count == #component then return "mir-only" end
  if planned_count > 0 then return "mixed-mir-external" end
  return "external-only"
end

local function reason_less(left, right)
  local left_priority = REJECTION_PRIORITY[left.code] or 1000
  local right_priority = REJECTION_PRIORITY[right.code] or 1000
  if left_priority ~= right_priority then return left_priority < right_priority end
  if left.code ~= right.code then return left.code < right.code end
  return tostring(left.evidence) < tostring(right.evidence)
end

local function add_reason(reasons, name, code, evidence, origin)
  local bucket = reasons[name]
  if not bucket then
    bucket = {local_by_identity = {}, local_reasons = {}, cause_links = {}, cause_link_set = {}}
    reasons[name] = bucket
  end
  local reason = {
    code = code,
    evidence = evidence,
    origin = origin or name,
    priority = REJECTION_PRIORITY[code] or 1000
  }
  local identity = tostring(code) .. "\0" .. tostring(reason.origin) .. "\0" .. tostring(evidence)
  if bucket.local_by_identity[identity] then return false end
  reason.identity = fingerprint.of({code = code, origin = reason.origin, evidence = evidence})
  bucket.local_by_identity[identity] = reason
  table.insert(bucket.local_reasons, reason)
  table.sort(bucket.local_reasons, reason_less)
  if not bucket.primary or reason_less(reason, bucket.primary) then bucket.primary = reason end
  return true
end

local function propagate_rejections(reasons, reverse)
  local queue = sorted_keys(reasons)
  local index = 1
  while index <= #queue do
    local unsafe_name = queue[index]
    index = index + 1
    local unsafe_bucket = reasons[unsafe_name]
    for _, dependent in ipairs(reverse[unsafe_name] or {}) do
      local bucket = reasons[dependent]
      if not bucket then
        bucket = {local_by_identity = {}, local_reasons = {}, cause_links = {}, cause_link_set = {}}
        reasons[dependent] = bucket
      end
      local changed = false
      if not bucket.cause_link_set[unsafe_name] then
        bucket.cause_link_set[unsafe_name] = true
        table.insert(bucket.cause_links, unsafe_name)
        table.sort(bucket.cause_links)
        changed = true
      end
      if unsafe_bucket.primary and (not bucket.primary or reason_less(unsafe_bucket.primary, bucket.primary)) then
        bucket.primary = unsafe_bucket.primary
        changed = true
      end
      if changed then table.insert(queue, dependent) end
    end
  end
end

local function resolved_reason(name, bucket, reasons)
  local primary = deepcopy(bucket.primary)
  local contributing, seen = {}, {}
  local function sample(reason)
    if not reason or (primary and reason.identity == primary.identity) or seen[reason.identity] then return end
    seen[reason.identity] = true
    if #contributing < CONTRIBUTING_SAMPLE_LIMIT then table.insert(contributing, deepcopy(reason)) end
  end
  for _, reason in ipairs(bucket.local_reasons) do sample(reason) end
  for _, upstream in ipairs(bucket.cause_links) do sample(reasons[upstream] and reasons[upstream].primary) end
  table.sort(contributing, reason_less)
  local local_origins = {}
  for _, reason in ipairs(bucket.local_reasons) do table.insert(local_origins, reason.identity) end
  table.sort(local_origins)
  local contributing_count = #bucket.local_reasons + #bucket.cause_links
  if primary then contributing_count = math.max(0, contributing_count - 1) end
  return primary, contributing, {
    contributing_count = contributing_count,
    contributing_samples_truncated = contributing_count > #contributing,
    contributing_origin_fingerprint = fingerprint.of({name = name, local_origins = local_origins, cause_links = bucket.cause_links}),
    cause_links = deepcopy(bucket.cause_links)
  }
end

function M.validate_operations(operations, options)
  telemetry.start_phase("graph")
  local technologies, planned, adjacency, reverse, edge_count, effect_count, snapshot = build_graph(operations, options)
  local rejection_reasons = {}
  for owner, prerequisites in pairs(adjacency) do
    for _, prerequisite in ipairs(prerequisites) do
      if not technologies[prerequisite] then
        add_reason(
          rejection_reasons,
          prerequisite,
          "prerequisite_missing",
          tostring(owner) .. " -> " .. tostring(prerequisite)
        )
      end
    end
  end
  for name, technology in pairs(technologies) do
    if technology.enabled == false then
      add_reason(rejection_reasons, name, "prerequisite_disabled", tostring(name))
    end
  end

  local names = sorted_keys(technologies)
  local scc_result = scc_kernel.analyze(adjacency)
  local components = {}
  for _, component in ipairs(scc_result.components) do table.insert(components, component.nodes) end
  local condensed = condensation.build(adjacency, scc_result.assignment)
  local component_count, cyclic_component_count = #components, 0
  local cyclic_components = {}
  for _, component in ipairs(components) do
    if component_is_cycle(component, adjacency) then
      cyclic_component_count = cyclic_component_count + 1
      local classification = cycle_class(component, planned)
      local actual_cycle_witness, witness_truncated = find_actual_cycle(
        component, adjacency, WITNESS_NODE_LIMIT)
      local witness = table.concat(actual_cycle_witness, " -> ")
      local member_sample = bounded_component_nodes(component)
      local internal_edges = component_internal_edges(component, adjacency)
      local component_member_id = fingerprint.of(component)
      local component_topology_fingerprint = fingerprint.of(internal_edges)
      table.insert(cyclic_components, {
        component_id = component_member_id,
        component_member_id = component_member_id,
        component_topology_fingerprint = component_topology_fingerprint,
        internal_edge_count = #internal_edges,
        classification = classification,
        node_count = #component,
        member_sample = member_sample,
        actual_cycle_witness = actual_cycle_witness,
        actual_cycle_witness_truncated = witness_truncated,
        nodes = member_sample,
        nodes_truncated = #component > WITNESS_NODE_LIMIT,
        witness = witness
      })
      telemetry.witness("technology_cycles", classification .. ":" .. witness)
      local code = classification == "mir-only" and "prerequisite_mir_cycle"
        or classification == "mixed-mir-external" and "prerequisite_mixed_cycle"
        or "prerequisite_external_cycle"
      for _, name in ipairs(component) do
        add_reason(rejection_reasons, name, code, witness,
          "component:" .. component_member_id .. ":" .. component_topology_fingerprint)
      end
    end
  end

  local proofs, research_rejections = {}, {}
  local nodes = graph_snapshot.technology_map(snapshot)
  local research_services = {
    valid_research_ingredients = science.valid_research_ingredients,
    pack_production_status = science.pack_production_status
  }
  for name in pairs(planned) do
    local code = researchability.evaluate(nodes[name], research_services)
    if code then research_rejections[name] = {code = code, evidence = tostring(name)} end
  end
  for name, reason in pairs(research_rejections) do
    add_reason(rejection_reasons, name, reason.code, reason.evidence)
  end
  propagate_rejections(rejection_reasons, reverse)

  local rejected, cause_graph = {}, {schema = 1, nodes = {}}
  for name, bucket in pairs(rejection_reasons) do
    local local_origins = {}
    for _, reason in ipairs(bucket.local_reasons) do table.insert(local_origins, deepcopy(reason)) end
    cause_graph.nodes[name] = {local_origins = local_origins, unsafe_prerequisites = deepcopy(bucket.cause_links)}
  end
  for name, _ in pairs(planned) do
    local reason_bucket = rejection_reasons[name]
    if reason_bucket then
      local primary, contributing, cause_summary = resolved_reason(name, reason_bucket, rejection_reasons)
      rejected[name] = {
        status = "failed",
        passed = false,
        code = primary.code,
        reason = primary.code,
        evidence = {"technology-graph:" .. primary.code, primary.evidence},
        primary = primary,
        contributing = contributing,
        contributing_count = cause_summary.contributing_count,
        contributing_samples_truncated = cause_summary.contributing_samples_truncated,
        contributing_origin_fingerprint = cause_summary.contributing_origin_fingerprint,
        cause_links = cause_summary.cause_links
      }
    else
      proofs[name] = gate_contract.passed(
        "technology-graph",
        {
          "technology-graph:scc-validated",
          "technology-graph:nodes=" .. tostring(#names),
          "technology-graph:edges=" .. tostring(edge_count)
        }
      )
    end
  end
  telemetry.count("technologies", #names)
  telemetry.count("effects", effect_count)
  telemetry.count("graph_edges", edge_count)
  telemetry.count("graph_components", component_count)
  telemetry.count("cyclic_components", cyclic_component_count)
  telemetry.finish_phase("graph")
  local result = {
    valid = true,
    graph_schema = snapshot.schema,
    graph_snapshot = snapshot,
    graph_fingerprint = snapshot.graph_fingerprint,
    component_assignments = scc_result.assignment,
    component_assignment_fingerprint = fingerprint.of(scc_result.assignment),
    condensation = condensed,
    condensation_topology_fingerprint = condensed.topology_fingerprint,
    node_count = #names,
    edge_count = edge_count,
    component_count = component_count,
    cyclic_component_count = cyclic_component_count,
    cyclic_components = cyclic_components,
    planned_technology_count = #sorted_keys(planned),
    accepted_planned_technology_count = #sorted_keys(proofs),
    rejected_planned_technology_count = #sorted_keys(rejected),
    proofs = proofs,
    rejected = rejected,
    cause_graph = cause_graph
  }
  result.proof_fingerprint = graph_evidence.proof_fingerprint(result)
  return result
end

return M
