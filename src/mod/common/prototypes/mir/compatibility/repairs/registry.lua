local M = {}

function M.apply()
  require("prototypes.mir.compatibility.repairs.factorio_2_1_recipe_schema").apply()
  require("prototypes.mir.compatibility.repairs.technology_prerequisite_cycles").apply()
end

return M
