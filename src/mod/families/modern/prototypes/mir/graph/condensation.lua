local fingerprint = require("prototypes.mir.core.fingerprint")

local M = {}

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
  return {schema = 1, edges = edges, topology_fingerprint = fingerprint.of(edges)}
end

return M
