-- The early target package has only a data-stage finite technology surface.
-- It intentionally has no startup settings, runtime control, migrations, or
-- unproven runtime adapters or infinite continuation definitions.
local definitions = require("adapters.early.definitions")
local generator = require("research.generator")

local M = {}

function M.apply(target)
  local stage = rawget(_G, "data")
  if type(stage) ~= "table" or type(stage.extend) ~= "function" then
    error("MIR early data adapter requires data:extend", 2)
  end
  generator.install(definitions.technologies(target, stage.raw), stage)
end

return M
