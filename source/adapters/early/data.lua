-- The early target package has only a data-stage finite technology surface.
-- It intentionally has no startup settings, runtime control, migrations, or
-- infinite continuation definitions because those APIs did not exist across
-- the admitted 0.6–0.12 engines.
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
