local M = {}

local function root()
  if type(global) == "table" then return global end
  if type(storage) == "table" then return storage end
  error("MIR runtime state is unavailable in this Factorio runtime.", 2)
end

function M.namespace()
  local state_root = root()
  state_root.mir = state_root.mir or {}
  return state_root.mir
end

function M.bucket(name)
  local namespace = M.namespace()
  namespace[name] = namespace[name] or {}
  return namespace[name]
end

return M
