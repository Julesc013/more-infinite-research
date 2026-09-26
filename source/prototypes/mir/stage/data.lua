local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

function M.run()
  require("prototypes.mir.streams.registry")
  -- The browser host exists only on the modern settings-profile targets.
  -- Keep the shared data stage from installing a dead shortcut on F100/F110.
  if not target_line.feature_enabled("settings_profiles") then return end
  data_raw.extend({{
    type = "shortcut",
    name = "mir-research-browser",
    order = "z[more-infinite-research]-a[research-browser]",
    action = "lua",
    toggleable = true,
    localised_name = {"mir-browser.shortcut-name"},
    localised_description = {"mir-browser.shortcut-description"},
    icon = "__base__/graphics/icons/lab.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/lab.png",
    small_icon_size = 64
  }})
end

return M
