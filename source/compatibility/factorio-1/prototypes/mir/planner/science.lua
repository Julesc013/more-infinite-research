local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")

local M = {}

function M.ingredients_for_stream(key, spec)
  local ingredients, lab_status = science_packs.best_lab_compatible_ingredients(science_selector.pick_science_for_stream(spec, key), key)
  return ingredients, lab_status or "full"
end

return M
