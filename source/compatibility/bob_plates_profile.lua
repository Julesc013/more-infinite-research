-- Pure selection shared by settings, data construction and runtime declarations.
-- Native route checks belong to the admitted material constructor.
local target = require("platform.target")
local M = {}
local REQUIRED = {"base", "boblibrary", "bobores", "bobplates"}
local ANGEL_OWNERSHIP_CONFLICT = "angelssmelting"

local function overlaps_bob_core(active)
  -- Bob Core is the separately authored F210 Space Age material owner.  The
  -- full Bob Base capture has bobelectronics and bobtech but no Space Age, so
  -- those names alone do not select or conflict with Bob Core.
  return active["space-age"] ~= nil and active.bobelectronics ~= nil and active.bobtech ~= nil
end

function M.select(active)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or target.minimum_base ~= "2.1.23"
      or type(active) ~= "table" then return nil end
  for _, name in ipairs(REQUIRED) do if active[name] == nil then return nil end end
  if active[ANGEL_OWNERSHIP_CONFLICT] ~= nil or overlaps_bob_core(active) then return nil end
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
