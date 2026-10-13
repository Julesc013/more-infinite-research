local M = {}
local compiler_profile = require("prototypes.mir.settings.compiler_profile")
local target_line = require("prototypes.mir.platform.factorio.target_line")

function M.run()
  if compiler_profile.get(target_line.factorio_version) == "classic" then
    return require("prototypes.mir.pipeline.classic_compiler").run()
  end
  return require("prototypes.mir.pipeline.commands").run_all({return_snapshot = false})
end

return M
