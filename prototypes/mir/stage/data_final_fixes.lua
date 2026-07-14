local M = {}
local commands = require("prototypes.mir.pipeline.commands")

function M.run()
  commands.run_all()
end

return M
