local recycling = require("prototypes.mir.index.recycling")

local M = {}

function M.approve(recipe)
  return recycling.classify(recipe)
end

return M
