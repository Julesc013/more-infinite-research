local registry_builder = require("prototypes.mir.index.registry_builder")

local M = {}

function M.all(registry)
  return (registry or registry_builder.build()).technologies or {}
end

function M.sorted_keys(technologies)
  return registry_builder.sorted_keys(technologies or {})
end

return M
