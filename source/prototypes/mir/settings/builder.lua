local registry = require("prototypes.mir.settings.registry")
local visibility = require("prototypes.mir.settings.visibility")

local M = {}

function M.evaluate_visibility(spec, ctx)
  return visibility.evaluate(spec, ctx)
end

function M.apply_visibility(setting, result)
  if result and result.visible == false then
    setting.hidden = true
  end
  return setting
end

function M.stream_setting_names(stream_key)
  local patterns = registry.stream_setting_group.setting_names
  return {
    enable = string.format(patterns.enable, stream_key),
    base_cost = string.format(patterns.base_cost, stream_key),
    growth = string.format(patterns.growth, stream_key),
    max_level = string.format(patterns.max_level, stream_key),
    research_time = string.format(patterns.research_time, stream_key)
  }
end

function M.add_stream_setting(settings_data, setting, stream, ctx)
  table.insert(settings_data, M.apply_visibility(setting, M.evaluate_visibility(stream, ctx)))
end

return M
