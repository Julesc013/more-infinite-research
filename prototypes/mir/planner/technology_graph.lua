local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local telemetry = require("prototypes.mir.report.compiler_telemetry")
local deepcopy = require("prototypes.mir.core.deepcopy")
local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}
local WITNESS_NODE_LIMIT = 64
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

local function build_graph(operations)
  local planned = planned_technologies(operations)
  local technologies = {}
  for name, technology in pairs(data_raw.prototypes("technology")) do technologies[name] = technology end
  for name, technology in pairs(planned) do technologies[name] = technology end

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
  return technologies, planned, adjacency, reverse, edge_count, effect_count
end

local function finish_order(names, adjacency)
  local visited, order = {}, {}
  for _, root in ipairs(names) do
    if not visited[root] then
      visited[root] = true
      local stack = {{name = root, next_index = 1}}
      while #stack > 0 do
        local frame = stack[#stack]
        local edges = adjacency[frame.name] or {}
        local next_name = edges[frame.next_index]
        if next_name then
          frame.next_index = frame.next_index + 1
          if adjacency[next_name] and not visited[next_name] then
            visited[next_name] = true
            table.insert(stack, {name = next_name, next_index = 1})
          end
        else
          table.insert(order, frame.name)
          table.remove(stack)
        end
      end
    end
  end
  return order
end

local function strongly_connected_components(order, reverse)
  local assigned, components = {}, {}
  for order_index = #order, 1, -1 do
    local root = order[order_index]
    if not assigned[root] then
      assigned[root] = true
      local component, stack = {}, {root}
      while #stack > 0 do
        local name = table.remove(stack)
        table.insert(component, name)
        local edges = reverse[name] or {}
        for index = #edges, 1, -1 do
          local next_name = edges[index]
          if not assigned[next_name] then
            assigned[next_name] = true
            table.insert(stack, next_name)
          end
        end
      end
      table.sort(component)
      table.insert(components, component)
    end
  end
  return components
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
    bucket = {by_origin = {}, all = {}}
    reasons[name] = bucket
  end
  local reason = {
    code = code,
    evidence = evidence,
    origin = origin or name,
    priority = REJECTION_PRIORITY[code] or 1000
  }
  local identity = tostring(code) .. "\0" .. tostring(reason.origin) .. "\0" .. tostring(evidence)
  if bucket.by_origin[identity] then return false end
  bucket.by_origin[identity] = reason
  table.insert(bucket.all, reason)
  table.sort(bucket.all, reason_less)
  return true
end

local function propagate_rejections(reasons, reverse)
  local queue = sorted_keys(reasons)
  local index = 1
  while index <= #queue do
    local unsafe_name = queue[index]
    index = index + 1
    for _, dependent in ipairs(reverse[unsafe_name] or {}) do
      local changed = false
      for _, reason in ipairs(reasons[unsafe_name].all) do
        changed = add_reason(
          reasons, dependent, reason.code, reason.evidence, reason.origin) or changed
      end
      if changed then table.insert(queue, dependent) end
    end
  end
end

local function resolved_reason(bucket)
  local primary = deepcopy(bucket.all[1])
  local contributing = {}
  for index = 2, #bucket.all do table.insert(contributing, deepcopy(bucket.all[index])) end
  return primary, contributing
end

function M.validate_operations(operations)
  telemetry.start_phase("graph")
  local technologies, planned, adjacency, reverse, edge_count, effect_count = build_graph(operations)
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
  local components = strongly_connected_components(finish_order(names, adjacency), reverse)
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
      local component_id = fingerprint.of(component)
      table.insert(cyclic_components, {
        component_id = component_id,
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
        add_reason(rejection_reasons, name, code, witness, "component:" .. component_id)
      end
    end
  end

  local proofs, research_rejections = {}, {}
  for name, technology in pairs(planned) do
    local unit = technology.unit
    if not unit or type(unit.ingredients) ~= "table" or #unit.ingredients == 0 then
      research_rejections[name] = {code = "research_mechanism_missing", evidence = tostring(name) .. ":ingredients"}
    elseif unit.count == nil and unit.count_formula == nil then
      research_rejections[name] = {code = "research_mechanism_missing", evidence = tostring(name) .. ":count"}
    elseif not science.valid_research_ingredients(unit.ingredients) then
      research_rejections[name] = {code = "research_lab_unavailable", evidence = tostring(name)}
    else
      for _, ingredient in ipairs(unit.ingredients) do
        local pack_name = ingredient.name or ingredient[1]
        if pack_name and science.pack_production_status(pack_name) == "unreachable" then
          research_rejections[name] = {
            code = "research_science_unreachable",
            evidence = tostring(name) .. ":" .. tostring(pack_name)
          }
          break
        end
      end
    end
  end
  for name, reason in pairs(research_rejections) do
    add_reason(rejection_reasons, name, reason.code, reason.evidence)
  end
  propagate_rejections(rejection_reasons, reverse)

  local rejected = {}
  for name, _ in pairs(planned) do
    local reason_bucket = rejection_reasons[name]
    if reason_bucket then
      local primary, contributing = resolved_reason(reason_bucket)
      rejected[name] = {
        status = "failed",
        passed = false,
        code = primary.code,
        reason = primary.code,
        evidence = {"technology-graph:" .. primary.code, primary.evidence},
        primary = primary,
        contributing = contributing
      }
    else
      proofs[name] = {
        status = "passed",
        passed = true,
        evidence = {
          "technology-graph:scc-validated",
          "technology-graph:nodes=" .. tostring(#names),
          "technology-graph:edges=" .. tostring(edge_count)
        }
      }
    end
  end
  telemetry.count("technologies", #names)
  telemetry.count("effects", effect_count)
  telemetry.count("graph_edges", edge_count)
  telemetry.count("graph_components", component_count)
  telemetry.count("cyclic_components", cyclic_component_count)
  telemetry.finish_phase("graph")
  return {
    valid = true,
    node_count = #names,
    edge_count = edge_count,
    component_count = component_count,
    cyclic_component_count = cyclic_component_count,
    cyclic_components = cyclic_components,
    planned_technology_count = #sorted_keys(planned),
    accepted_planned_technology_count = #sorted_keys(proofs),
    rejected_planned_technology_count = #sorted_keys(rejected),
    proofs = proofs,
    rejected = rejected
  }
end

return M
