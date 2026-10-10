local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")
local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

function M.run()
  require("prototypes.mir.streams.registry")
  -- Library availability is independent of optional settings-profile tools.
  -- Historical targets keep this off until their host adapters are qualified.
  if not target_line.feature_enabled("research_library") then return end
  -- Only an active provider establishes that its resource root is available.
  -- A saved/imported cosmetic preference cannot prove installed DLC files.
  -- Share the same stage-safe provider query as the technology icon builder.
  local use_space_age_art = factorio_mods.exists("space-age")
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
