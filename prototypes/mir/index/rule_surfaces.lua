local registry_builder = require("prototypes.mir.index.registry_builder")

local M = {}

function M.rule_mutations(registry)
  return (registry or registry_builder.build()).rule_mutations or {}
end

function M.loop_risks(registry)
  return (registry or registry_builder.build()).loop_risks or {}
end

return M
