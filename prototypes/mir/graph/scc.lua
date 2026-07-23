local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function sorted_keys(values)
  local out = {}
  for key in pairs(values or {}) do table.insert(out, key) end
  table.sort(out)
  return out
end

function M.analyze(adjacency)
  local names = sorted_keys(adjacency)
  local reverse = {}
  for _, name in ipairs(names) do reverse[name] = {} end
  for owner, edges in pairs(adjacency or {}) do
    for _, target in ipairs(edges or {}) do
      if adjacency[target] then table.insert(reverse[target], owner) end
    end
  end
  for _, edges in pairs(reverse) do table.sort(edges) end

  local visited, order = {}, {}
  for _, root in ipairs(names) do
    if not visited[root] then
      visited[root] = true
      local stack = {{name = root, next_index = 1}}
      while #stack > 0 do
        local frame = stack[#stack]
        local next_name = (adjacency[frame.name] or {})[frame.next_index]
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

  local assigned, components, assignment = {}, {}, {}
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
          if not assigned[next_name] then assigned[next_name] = true; table.insert(stack, next_name) end
        end
      end
      table.sort(component)
      local id = fingerprint.of(component)
      table.insert(components, {component_id = id, nodes = component})
      for _, name in ipairs(component) do assignment[name] = id end
    end
  end
  table.sort(components, function(left, right) return left.component_id < right.component_id end)
  return {schema = 1, components = components, assignment = assignment}
end

return M
