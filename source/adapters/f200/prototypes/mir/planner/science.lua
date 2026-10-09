local science_packs = require("prototypes.mir.capabilities.science_integration.science_packs")
local science_selector = require("prototypes.mir.capabilities.science_integration.science_selector")

local M = {}

function M.ingredients_for_selected(key, selected)
  local ingredients, lab_status = science_packs.best_lab_compatible_ingredients(
    selected,
    key,
    science_selector.required_science_packs_for_stream(key)
  )
  return ingredients, lab_status or "full"
end

function M.ingredients_for_stream(key, spec)
  return M.ingredients_for_selected(key,
    science_selector.pick_science_for_stream(spec, key))
end

return M
