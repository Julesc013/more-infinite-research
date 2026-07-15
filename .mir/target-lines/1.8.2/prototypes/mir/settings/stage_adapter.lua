local factorio_mods = require("prototypes.mir.platform.factorio.mods")
local builder = require("prototypes.mir.settings.builder")

local M = {}

function M.context()
  return {
    mods = factorio_mods.snapshot()
  }
end

function M.visibility_for_stream(stream, ctx)
  return builder.evaluate_visibility(stream, ctx)
end

function M.apply(setting, visibility_result)
  return builder.apply_visibility(setting, visibility_result)
end

function M.add(settings_data, setting, visibility_result)
  table.insert(settings_data, M.apply(setting, visibility_result))
end

return M
