local M = {}
local compiler_context = require("prototypes.mir.pipeline.compiler_context")

local function entries()
  return compiler_context.current():state_view("generated_technology_registry", function() return {} end)
end

function M.register(name, metadata)
  if not name then return end
  local registry = entries()
  local entry = registry[name] or { name = name }
  for key, value in pairs(metadata or {}) do entry[key] = value end
  registry[name] = entry
end

function M.contains(name)
  return entries()[name] ~= nil
end

function M.get(name)
  return entries()[name]
end

function M.sorted_names(options)
  options = options or {}
  local out = {}
  for name, entry in pairs(entries()) do
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
