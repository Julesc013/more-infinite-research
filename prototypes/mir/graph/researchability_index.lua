local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local scc_kernel = require("prototypes.mir.graph.scc")

local M = {}

local function sorted_prerequisites(technology)
  local out = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(out, prerequisite)
  end
  table.sort(out)
  return out
end

function M.build()
  local technologies, adjacency = {}, {}
  for name, technology in pairs(data_raw.prototypes("technology")) do technologies[name] = technology end
  for name, technology in pairs(technologies) do adjacency[name] = sorted_prerequisites(technology) end
  local analysis = scc_kernel.analyze(adjacency)
  local cyclic_components = {}
  for _, component in ipairs(analysis.components) do
    local cyclic = #component.nodes > 1
    if #component.nodes == 1 then
      for _, prerequisite in ipairs(adjacency[component.nodes[1]] or {}) do
        if prerequisite == component.nodes[1] then cyclic = true end
      end
    end
    if cyclic then cyclic_components[component.component_id] = true end
  end

  local structural, visiting = {}, {}
  local function classify(name)
    if structural[name] ~= nil then return structural[name] or nil end
    local technology = technologies[name]
    if not technology then structural[name] = "missing-prerequisite-" .. tostring(name); return structural[name] end
    if technology.enabled == false then
      structural[name] = "disabled-prerequisite-" .. tostring(name)
      return structural[name]
    end
    local component_id = analysis.assignment[name]
    if component_id and cyclic_components[component_id] then
      structural[name] = "technology-cycle-" .. tostring(component_id)
      return structural[name]
    end
    if visiting[name] then
      structural[name] = "technology-cycle-" .. tostring(name)
      return structural[name]
    end
    visiting[name] = true
    for _, prerequisite in ipairs(adjacency[name] or {}) do
      local failure = classify(prerequisite)
      if failure then structural[name] = failure; visiting[name] = nil; return failure end
    end
    visiting[name] = nil
    structural[name] = false
    return nil
  end
  for name in pairs(technologies) do classify(name) end

  local snapshot = graph_snapshot.new(technologies)
  local index = {
    schema = 1,
    adjacency = adjacency,
    component_assignments = analysis.assignment,
    structural_failures = structural,
    node_count = #snapshot.nodes,
    graph_fingerprint = snapshot.graph_fingerprint
  }
  index.index_fingerprint = fingerprint.of(index)
  return index
end

function M.reachable_names(index, root_name)
  local seen, queue, out = {}, {root_name}, {}
  local cursor = 1
  while cursor <= #queue do
    local name = queue[cursor]
    cursor = cursor + 1
    if not seen[name] then
      seen[name] = true
      table.insert(out, name)
      for _, prerequisite in ipairs(index.adjacency[name] or {}) do table.insert(queue, prerequisite) end
    end
  end
  table.sort(out)
  return out
end

return M
