local M = {}

local names = {}

function M.register(name)
  if name then names[name] = true end
end

function M.contains(name)
  return names[name] == true
end

function M.sorted_names()
  local out = {}
  for name, _ in pairs(names) do table.insert(out, name) end
  table.sort(out)
  return out
end

return M
