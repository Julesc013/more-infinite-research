-- Pure F210 Bob+Angel selection shared by settings, catalogue, and runtime
-- declarations.  It deliberately consumes only the named providers whose
-- authored routes or science vectors the companion data module uses.  Raw
-- prototype validation remains in that module's data-stage preflight.
local target = require("platform.target")

local M = {}

local REQUIRED = {
  "base",
  "angelsbioprocessing", "angelspetrochem", "angelsrefining", "angelssmelting",
  "bobelectronics", "bobplates", "bobrevamp", "bobtech",
}

-- These are separate, independently-authored F210 bindings.  Returning nil
-- here keeps their profile-specific data from being accidentally composed
-- with the q009/q010 Bob+Angel facts.  This is not a general compatibility
-- classifier or a version fingerprint.
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
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or target.minimum_base ~= "2.1.23"
      or type(active) ~= "table" or not all_present(active, REQUIRED) then
    return nil
  end
  for _, name in ipairs(INCOMPATIBLE) do
    if active[name] ~= nil then return nil end
  end
  return active["space-age"] ~= nil and "space-age" or "base"
end

function M.applies(active)
  return M.select(active) ~= nil
end

return M
