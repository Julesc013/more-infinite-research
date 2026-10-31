-- Pure Angel F210 selection.  This only selects the independently captured
-- provider family; it does not inspect prototypes, settings, or saved state.
-- The root catalogue supplies the F210 target gate before using this module.
local M = {}

local REQUIRED = {
  "angelsbioprocessing",
  "angelspetrochem",
  "angelsrefining",
  "angelssmelting",
}

function M.select(active_mods)
  if type(active_mods) ~= "table" then return nil end
  for _, name in ipairs(REQUIRED) do
    if active_mods[name] == nil then return nil end
  end

  -- q009 establishes that Bob Plates changes the aluminium route and the
  -- combined profile's science.  It is intentionally outside this adapter.
  if active_mods.bobplates ~= nil then return nil end
  return active_mods["space-age"] ~= nil and "space-age" or "base"
end

function M.applies(active_mods)
  return M.select(active_mods) ~= nil
end

return M
