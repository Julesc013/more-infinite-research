local technology_design = require("prototypes.mir.domain.technology.technology_design")
local technology_design_adapter = require("prototypes.mir.emit.technology_design_adapter")

local M = {}

function M.emit(design)
  technology_design.validate(design)
  local identity = design.design.identity.value
  local key = identity.stream_key
  return technology_design_adapter.emit(design, {kind = "stream", key = key})
end

return M
