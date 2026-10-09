local registry_builder = require("prototypes.mir.index.registry_builder")

local M = {}

function M.all(registry)
  return (registry or registry_builder.build()).owners or {}
end

return M
