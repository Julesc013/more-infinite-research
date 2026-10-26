-- Pure selection shared by settings, data construction and runtime declarations.
-- Native route checks belong to the admitted material constructor.
local target = require("platform.target")
local M = {}
local REQUIRED = {"base", "boblibrary", "bobores", "bobplates"}
local OWNERSHIP_CONFLICTS = {"bobelectronics", "bobtech", "angelssmelting"}

function M.select(active)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or target.minimum_base ~= "2.1.23"
      or type(active) ~= "table" then return nil end
  for _, name in ipairs(REQUIRED) do if active[name] == nil then return nil end end
  for _, name in ipairs(OWNERSHIP_CONFLICTS) do if active[name] ~= nil then return nil end end
  return active["space-age"] ~= nil and "space-age" or "base"
end

function M.applies(active) return M.select(active) ~= nil end

function M.visible_families(profile)
  local visible = {}
  if profile == nil then return visible end
  local definitions = require("research.bob_plates_materials")
  for _, definition in ipairs(definitions.material_definitions(profile)) do visible[definition.key] = true end
  for _, definition in ipairs(definitions.product_definitions(profile)) do visible[definition.key] = true end
  return visible
end

return M
