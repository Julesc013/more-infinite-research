local registry_builder = require("prototypes.mir.index.registry_builder")

local M = {}

function M.all(registry)
  return (registry or registry_builder.build()).labs or {}
end

function M.for_packs(labs, packs)
  return registry_builder.labs_for_packs(labs or {}, packs or {})
end

function M.sorted_keys(labs)
  return registry_builder.sorted_keys(labs or {})
end

return M
