-- F200 2.0 Space Age + BobTech selection for the independently captured
-- combined profile. This is a named provider gate, not a complete-modpack
-- fingerprint: data-stage preflight validates every raw prototype that the
-- accompanying authored delta consumes.
local target = require("platform.target")

local M = {}

local REQUIRED = {
  "base", "space-age",
  "angelsbioprocessing", "angelspetrochem", "angelsrefining", "angelssmelting",
  "bobelectronics", "boblibrary", "boblogistics", "bobores", "bobplates", "bobrevamp", "bobtech",
}

local INCOMPATIBLE = {
  "Krastorio2", "Krastorio2-spaced-out",
  "pycoalprocessing", "pyalienlife", "pyhightech", "space-exploration",
}

local function all_present(active, names)
  for _, name in ipairs(names) do
    if active[name] == nil then return false end
  end
  return true
end

function M.select(active)
  if target.id ~= "f200" or target.factorio_version ~= "2.0" or target.minimum_base ~= "2.0.77"
      or type(active) ~= "table" or not all_present(active, REQUIRED) then
    return nil
  end
  for _, name in ipairs(INCOMPATIBLE) do
    if active[name] ~= nil then return nil end
  end
  return "space-age-bobtech"
end

function M.applies(active)
  return M.select(active) ~= nil
end

return M
