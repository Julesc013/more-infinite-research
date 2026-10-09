local technology_design_adapter = require("prototypes.mir.emit.technology_design_adapter")

local M = {}

function M.emit(design)
  -- The shared adapter owns the single full validation and derives the stream
  -- key only after that proof succeeds.
  return technology_design_adapter.emit(design, {kind = "stream"})
end

return M
