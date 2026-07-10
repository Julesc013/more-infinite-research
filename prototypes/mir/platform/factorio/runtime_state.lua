local target_line = require("prototypes.mir.platform.factorio.target_line")

local M = {}

function M.root()
  local backend = target_line.runtime_state_backend()
  if backend == "storage" then
    if type(storage) ~= "table" then
      error("MIR target profile requires Factorio storage runtime state, but storage is unavailable.", 2)
    end
    return storage
  end
  if backend == "global" then
    if type(global) ~= "table" then
      error("MIR target profile requires Factorio global runtime state, but global is unavailable.", 2)
    end
    return global
  end
  error("MIR target profile selected unsupported runtime state backend " .. tostring(backend) .. ".", 2)
end

return M
