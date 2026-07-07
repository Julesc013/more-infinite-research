local U = require("prototypes.util")

local M = {}

function M.ingredients_for_stream(key, spec)
  local ingredients, lab_status = U.best_lab_compatible_ingredients(U.pick_science_for_stream(spec, key), key)
  return ingredients, lab_status or "full"
end

return M
