local registry_builder = require("prototypes.mir.index.registry_builder")

local M = {}

function M.all(registry)
  return (registry or registry_builder.build()).recipes or {}
end

function M.sorted_keys(recipes)
  return registry_builder.sorted_keys(recipes or {})
end

return M
