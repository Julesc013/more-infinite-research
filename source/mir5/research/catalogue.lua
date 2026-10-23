-- Declared MIR identities for the first Library slice. This is metadata only:
-- native technology and force state are read by presentation.library_model.
local M = {}
local GEAR_ID = "recipe-prod-research_gears-1"

function M.gear_id()
  return GEAR_ID
end

local GEAR_SETTINGS = {
  "ips-enable-research_gears",
  "ips-cost-base-research_gears",
  "ips-cost-linear-increment-research_gears",
  "ips-cost-growth-research_gears",
  "ips-max-level-research_gears",
  "ips-research-time-research_gears",
  "ips-effect-per-level-research_gears"
}

local function copy_settings()
  local result = {}
  for index = 1, #GEAR_SETTINGS do result[index] = GEAR_SETTINGS[index] end
  return result
end

-- A fresh table prevents a presentation caller from retaining or changing
-- declaration state. Add future authored identities here, not a world scan.
function M.declared()
  return {{
    id = GEAR_ID,
    family = "mir",
    progression = 1,
    native_order = "p[research_gears]",
    setting = "ips-enable-research_gears",
    settings = copy_settings(),
    cap_setting = "ips-max-level-research_gears",
    recipe = "iron-gear-wheel",
    locale_key = "technology-name.more-infinite-research.research_gears"
  }}
end

return M
