local M = {}
local factorio_mods = require("prototypes.mir.platform.factorio.mods")

function M.apply(options)
  require("prototypes.mir.compatibility.repairs.factorio_2_1_recipe_schema").apply()
  if factorio_mods.exists("angelssmelting") then
    require("prototypes.mir.compatibility.repairs.angels_smelting").apply()
  end
  local result = require("prototypes.mir.compatibility.repairs.technology_prerequisite_cycles").apply(options)
  -- Keep the historical Full entry point's nil result intact.  Classic alone
  -- receives the bounded cycle-repair observation for its compact audit path.
  if type(options) == "table" and options.bounded == true then return result end
end

return M
