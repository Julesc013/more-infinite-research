-- Pure authored selection facts shared by the Bob Core gate and Library.
-- No prototype reads, construction, state mutation or target-package import.
local M = {}

local REQUIRED = {
  "base", "space-age", "boblibrary", "bobores", "bobplates", "bobelectronics", "bobtech",
}
local ANGEL = {
  "angelsbioprocessing", "angelsbioprocessinggraphics", "angelsrefining", "angelsrefininggraphics",
  "angelspetrochem", "angelspetrochemgraphics", "angelssmelting", "angelssmeltinggraphics",
}
local UNSUPPORTED = {
  "Krastorio2", "Krastorio2-spaced-out", "pycoalprocessing", "pyalienlife", "pyhightech",
}

local function any_active(active, names)
  for _, name in ipairs(names) do if active[name] ~= nil then return true end end
  return false
end

function M.status(active, target)
  if type(target) ~= "table" or target.id ~= "f210" or target.factorio_version ~= "2.1"
      or type(active) ~= "table" then return "unrelated" end
  for _, name in ipairs(REQUIRED) do if active[name] == nil then return "unrelated" end end
  if any_active(active, ANGEL) then return "unrelated" end
  if target.minimum_base ~= "2.1.23" then return "unsupported-floor" end
  if any_active(active, UNSUPPORTED) then return "unsupported-overhaul" end
  return "selected"
end

return M
