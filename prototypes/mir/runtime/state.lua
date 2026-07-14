local M = {}
local runtime_state = require("prototypes.mir.platform.factorio.runtime_state")

function M.namespace()
  local state_root = runtime_state.root()
  state_root.mir = state_root.mir or {}
  return state_root.mir
end

function M.bucket(name)
  local namespace = M.namespace()
  namespace[name] = namespace[name] or {}
  return namespace[name]
end

return M
