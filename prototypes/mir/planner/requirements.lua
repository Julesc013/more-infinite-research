local U = require("prototypes.util")
local technology_requirements = require("prototypes.lib.technology-requirements")

local M = {}

function M.missing_reason(key, spec)
  for _, mod_name in ipairs(spec.required_mods or {}) do
    if not U.mod_exists(mod_name) then
      return "missing required mod " .. mod_name
    end
  end

  for _, item_name in ipairs(spec.required_items or {}) do
    if not U.item_prototype(item_name) then
      return "missing required item " .. item_name
    end
  end

  for _, fluid_name in ipairs(spec.required_fluids or {}) do
    if not U.fluid_prototype(fluid_name) then
      return "missing required fluid " .. fluid_name
    end
  end

  for _, tech_name in ipairs(spec.required_technologies or {}) do
    if not U.technology_exists(tech_name) then
      return "missing required technology " .. tech_name
    end
  end

  local skip_reason = technology_requirements.skip_reason(spec)
  if skip_reason then return skip_reason end

  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not U.ammo_category_exists(category) then
      return "missing required ammo category " .. category
    end
  end

  return nil
end

return M
