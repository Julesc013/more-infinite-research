local registry = require("prototypes.mir.compatibility.registry")

local M = {}

function M.overlays()
  return registry.overlays
end

function M.get(id)
  for _, overlay in ipairs(registry.overlays or {}) do
    if overlay.id == id then return overlay end
  end
  return nil
end

return M
