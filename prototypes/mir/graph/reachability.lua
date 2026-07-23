local M = {}

function M.reverse(adjacency)
  local out = {}
  for owner in pairs(adjacency or {}) do out[owner] = out[owner] or {} end
  for owner, targets in pairs(adjacency or {}) do
    for _, target in ipairs(targets or {}) do
      out[target] = out[target] or {}
      table.insert(out[target], owner)
    end
  end
  for _, values in pairs(out) do table.sort(values) end
  return out
end

return M
