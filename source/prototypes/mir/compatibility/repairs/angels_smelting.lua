local data_raw = require("prototypes.mir.platform.factorio.data_raw")
local factorio_mods = require("prototypes.mir.platform.factorio.mods")
local diagnostics = require("prototypes.mir.report.diagnostics_sink")

local M = {}
local silver = "angels-silver-smelting-1"

function M.apply()
  if not factorio_mods.exists("angelssmelting") then return false end
  local technologies = data_raw.prototypes("technology")
  local modules, prerequisite = technologies.modules, technologies[silver]
  if not modules or modules.enabled == false or not prerequisite
    or prerequisite.enabled ~= false or type(modules.prerequisites) ~= "table" then return false end

  -- Angel can disable its unused silver chain. Repair only the reported
  -- stale modules edge; enabled silver and every other prerequisite remain.
  local prerequisites, removed = {}, false
  for _, name in ipairs(modules.prerequisites) do
    if name == silver then removed = true
    else prerequisites[#prerequisites + 1] = name end
  end
  if not removed then return false end
  modules.prerequisites = #prerequisites > 0 and prerequisites or nil
  diagnostics.compatibility_plan({
    key = "angels-disabled-silver-modules-prerequisite", status = "repaired",
    reason = "disabled-external-technology-prerequisite", technology = "modules",
    prerequisites = silver, evidence = "angelssmelting:" .. tostring(factorio_mods.version("angelssmelting"))
      .. ":silver-technology-disabled"
  })
  if log then log("[more-infinite-research] Removed disabled Angel silver prerequisite from modules.") end
  return true
end

return M
