-- Authored MIR identities for the Library. This metadata never discovers a
-- native technology: each declaration names a published player-facing row.
local M = {}

local GEAR_ID = "recipe-prod-research_gears-1"
local AGRICULTURE_ID = "recipe-prod-research_agricultural_growth_speed-1"
local SPOILAGE_ID = "recipe-prod-research_spoilage_preservation-1"

function M.gear_id()
  return GEAR_ID
end

local function stream_settings(key)
  return {
    "ips-enable-" .. key,
    "ips-cost-base-" .. key,
    "ips-cost-linear-increment-" .. key,
    "ips-cost-growth-" .. key,
    "ips-max-level-" .. key,
    "ips-research-time-" .. key,
    "ips-effect-per-level-" .. key
  }
end

local DECLARATIONS = {
  {
    id = GEAR_ID,
    family = "research_gears",
    progression = 1,
    native_order = "p[research_gears]",
    setting = "ips-enable-research_gears",
    cap_setting = "ips-max-level-research_gears",
    recipe = "iron-gear-wheel",
    locale_key = "technology-name.more-infinite-research.research_gears"
  },
  {
    id = AGRICULTURE_ID,
    family = "research_agricultural_growth_speed",
    progression = 1,
    native_order = "p[research_agricultural_growth_speed]",
    setting = "ips-enable-research_agricultural_growth_speed",
    cap_setting = "ips-max-level-research_agricultural_growth_speed",
    locale_key = "technology-name.more-infinite-research.research_agricultural_growth_speed"
  },
  {
    id = SPOILAGE_ID,
    family = "research_spoilage_preservation",
    progression = 1,
    native_order = "p[research_spoilage_preservation]",
    setting = "ips-enable-research_spoilage_preservation",
    cap_setting = "ips-max-level-research_spoilage_preservation",
    locale_key = "technology-name.more-infinite-research.research_spoilage_preservation"
  }
}

local function copy_row(source)
  local result = {}
  for name, value in pairs(source) do result[name] = value end
  result.settings = stream_settings(source.family)
  return result
end

-- A fresh table prevents a presentation caller from retaining or changing
-- declaration state. The direct effects are declared here even in a base-only
-- control stage; the Library still obtains native state on demand and never
-- creates an unavailable technology from this metadata.
function M.declared()
  local result = {}
  for index = 1, #DECLARATIONS do result[index] = copy_row(DECLARATIONS[index]) end
  return result
end

return M
