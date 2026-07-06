local registry = require("prototypes.mir.compatibility.registry")

local M = {}

function M.overlays()
  return registry.overlays
end

return M
