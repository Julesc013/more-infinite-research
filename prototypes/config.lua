local M = {}

M.shared = {
  per_level_default = 0.10,
  base_cost = 8000,
  growth_factor = 2,
  research_time = 60
}

M.streams = require("prototypes.streams.init")

require("prototypes.mir.compatibility.profiles").apply(M)

return M
