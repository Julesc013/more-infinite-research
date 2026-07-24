local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

local function quote(value, cache)
  local encoded = cache[value]
  if encoded then return encoded end
  encoded = string.format("%q", value)
  cache[value] = encoded
  return encoded
end

local function canonical_edges(edges)
  local out, cache = {"["}, {}
  for index, edge in ipairs(edges) do
    if index > 1 then out[#out + 1] = "," end
    out[#out + 1] = '{"from":'
    out[#out + 1] = quote(edge.from, cache)
    out[#out + 1] = ',"to":'
    out[#out + 1] = quote(edge.to, cache)
    out[#out + 1] = "}"
  end
  out[#out + 1] = "]"
  return table.concat(out)
end

function M.build(adjacency, assignment)
  local seen, edges = {}, {}
  for owner, targets in pairs(adjacency or {}) do
    local from = assignment[owner]
    for _, target in ipairs(targets or {}) do
      local to = assignment[target]
      if from and to and from ~= to then
        local key = from .. "\0" .. to
        if not seen[key] then seen[key] = true; table.insert(edges, {from = from, to = to}) end
      end
    end
  end
  table.sort(edges, function(left, right)
    if left.from ~= right.from then return left.from < right.from end
    return left.to < right.to
  end)
  return {
    schema = 1,
    edges = edges,
    topology_fingerprint = fingerprint.of_prebuilt_canonical(canonical_edges(edges))
  }
end

return M
