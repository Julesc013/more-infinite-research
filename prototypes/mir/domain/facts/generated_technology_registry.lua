local M = {}

local entries = {}

function M.register(name, metadata)
  if not name then return end
  local entry = entries[name] or { name = name }
  for key, value in pairs(metadata or {}) do entry[key] = value end
  entries[name] = entry
end

function M.contains(name)
  return entries[name] ~= nil
end

function M.get(name)
  return entries[name]
end

function M.sorted_names(options)
  options = options or {}
  local out = {}
  for name, entry in pairs(entries) do
    local matches = true
    for key, value in pairs(options) do
      if entry[key] ~= value then
        matches = false
        break
      end
    end
    if matches then table.insert(out, name) end
  end
  table.sort(out)
  return out
end

return M
