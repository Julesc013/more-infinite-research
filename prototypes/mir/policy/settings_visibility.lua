local factorio_mods = require("prototypes.mir.platform.factorio.mods")

local M = {}

function M.hidden_for_stream(stream)
  local required_mods = (stream and stream.settings_required_mods) or (stream and stream.required_mods)
  if not required_mods or #required_mods == 0 then return false end
  return not factorio_mods.all_exist(required_mods)
end

function M.apply(setting, hidden)
  if hidden then setting.hidden = true end
  return setting
end

return M
