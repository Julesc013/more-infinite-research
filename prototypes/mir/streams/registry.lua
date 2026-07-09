local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")

M.shared = {
  per_level_default = 0.10,
  base_cost = 8000,
  growth_factor = 2,
  research_time = 60
}

M.streams = require("prototypes.streams.init")
for key, spec in pairs(M.streams) do
  if not target_line.stream_supported(key, spec) then
    M.streams[key] = nil
  end
end

require("prototypes.mir.compatibility.profiles").apply(M)

return M
