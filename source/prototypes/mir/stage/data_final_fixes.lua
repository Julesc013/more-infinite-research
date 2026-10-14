local M = {}

function M.run()
  return require("prototypes.mir.pipeline.commands").run_all({return_snapshot = false})
end

return M
