local M = {}

local diagnostics = {
  {
    id = "air-scrubbing",
    module = require("prototypes.mir.compatibility.diagnostics.air_scrubbing")
  },
  {
    id = "atan-ash",
    module = require("prototypes.mir.compatibility.diagnostics.atan_ash")
  }
}

function M.all()
  return diagnostics
end

function M.emit_all()
  for _, entry in ipairs(diagnostics) do
    entry.module.emit()
  end
end

return M
