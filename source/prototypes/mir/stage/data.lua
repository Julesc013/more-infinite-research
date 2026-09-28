local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")

function M.run()
  require("prototypes.mir.streams.registry")
  -- The browser host exists only on the modern settings-profile targets.
  -- Keep the shared data stage from installing a dead shortcut on F100/F110.
  if not target_line.feature_enabled("settings_profiles") then return end
  local use_space_age_art = mods["space-age"] ~= nil
    or (settings.startup["mir-use-installed-space-age-icons"]
      and settings.startup["mir-use-installed-space-age-icons"].value == true)
  local icon = use_space_age_art
    and "__space-age__/graphics/technology/research-productivity.png"
    or "__base__/graphics/icons/lab.png"
  local icon_size = use_space_age_art and 256 or 64
  data_raw.extend({{
    type = "shortcut",
    name = "mir-research-browser",
    order = "z[more-infinite-research]-a[research-browser]",
    action = "lua",
    toggleable = true,
    localised_name = {"mir-browser.shortcut-name"},
    localised_description = {"mir-browser.shortcut-description"},
    icon = icon,
    icon_size = icon_size,
    small_icon = icon,
    small_icon_size = icon_size
  }})
end

return M
