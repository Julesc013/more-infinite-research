-- Authored Space Age settings stay outside the base settings module so a
-- base-only data/control stage never constructs this integration's rows.
local M = {}

M.streams = {
  {
    key = "research_spoilage_preservation",
    value_key = "spoilage_preservation",
    technology_locale = "technology-name.more-infinite-research.research_spoilage_preservation",
    order_prefix = "b-000-spoilage-preservation-stream-research_spoilage_preservation-",
    defaults = {enabled = true, base_cost = 50000, linear_increment = 0,
      growth_factor = 1.5, max_level = 0, research_time = 120, effect_percent = 1},
    enable_note = "mod-setting-description.mir-note-experimental-spoilage"
  },
  {
    key = "research_agricultural_growth_speed",
    value_key = "agricultural_growth_speed",
    technology_locale = "technology-name.more-infinite-research.research_agricultural_growth_speed",
    order_prefix = "b-050-agricultural-growth-speed-stream-research_agricultural_growth_speed-",
    defaults = {enabled = true, base_cost = 40000, linear_increment = 0,
      growth_factor = 1.5, max_level = 0, research_time = 90, effect_percent = 1},
    description_note = "mod-setting-description.mir-note-agriculture-growth"
  }
}

return M
