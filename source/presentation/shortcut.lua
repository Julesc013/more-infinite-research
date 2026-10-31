-- Data-stage shortcut declaration for the private MIR5 Library slice.
--
-- The caller owns data:extend and decides whether the active target supplies
-- Space Age artwork. Keeping this constructor pure makes the published
-- shortcut identity inspectable without importing the old compiler or a
-- Factorio data global.
local M = {}

function M.research_library_shortcut(has_space_age)
  local space_age = has_space_age == true
  local icon = space_age
    and "__space-age__/graphics/technology/research-productivity.png"
    or "__base__/graphics/icons/lab.png"
  local icon_size = space_age and 256 or 64

  return {
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
  }
end

return M
