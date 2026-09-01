local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local fingerprint = require("prototypes.mir.core.fingerprint")
local graph_snapshot = require("prototypes.mir.graph.snapshot")
local scc_kernel = require("prototypes.mir.graph.scc")
local condensation = require("prototypes.mir.graph.condensation")

local M = {}

local function sorted_prerequisites(technology)
  local out = {}
  for _, prerequisite in ipairs((technology and technology.prerequisites) or {}) do
    table.insert(out, prerequisite)
  end
  table.sort(out)
  return out
end

function M.build_from(technology_source)
  local technologies, adjacency = {}, {}
  for name, technology in pairs(technology_source or {}) do technologies[name] = technology end
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

  local structural, depths = {}, {}
  for name, technology in pairs(technologies) do
    if technology.enabled == false then
      structural[name] = "disabled-prerequisite-" .. tostring(name)
    else
      local component_id = analysis.assignment[name]
      if component_id and cyclic_components[component_id] then
        structural[name] = "technology-cycle-" .. tostring(component_id)
      end
    end
  end
  local names = {}
  for name in pairs(technologies) do table.insert(names, name) end
  table.sort(names)
  for _, root in ipairs(names) do
    if structural[root] == nil then
      local stack = {{name = root, next_index = 1, max_depth = -1}}
      while #stack > 0 do
        local frame = stack[#stack]
        local prerequisite = (adjacency[frame.name] or {})[frame.next_index]
        if not prerequisite then
          structural[frame.name] = false
          depths[frame.name] = frame.max_depth + 1
          table.remove(stack)
        elseif not technologies[prerequisite] then
          structural[frame.name] = "missing-prerequisite-" .. tostring(prerequisite)
          table.remove(stack)
        elseif structural[prerequisite] == nil then
          table.insert(stack, {name = prerequisite, next_index = 1, max_depth = -1})
        else
          frame.next_index = frame.next_index + 1
          local failure = structural[prerequisite]
          if failure then
            structural[frame.name] = failure
            table.remove(stack)
          else
            frame.max_depth = math.max(frame.max_depth, depths[prerequisite] or 0)
          end
        end
      end
    end
  end

  local snapshot = graph_snapshot.new(technologies)
  local topology = condensation.build(adjacency, analysis.assignment)
  local max_depth = 0
  for _, depth in pairs(depths) do max_depth = math.max(max_depth, depth) end
  local index = {
    schema = 2,
    adjacency = adjacency,
    component_assignments = analysis.assignment,
    condensation = topology,
    structural_failures = structural,
    unlock_depths = depths,
    max_unlock_depth = max_depth,
    node_count = #snapshot.nodes,
    graph_fingerprint = snapshot.graph_fingerprint
  }
  index.index_fingerprint = fingerprint.of(index)
  return index
end

function M.build()
  return M.build_from(data_raw.prototypes("technology"))
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
