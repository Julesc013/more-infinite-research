local lookup = require("prototypes.mir.platform.factorio.prototype_lookup")
local science = require("prototypes.mir.capabilities.science_integration.science_packs")
local technology_requirements = require("prototypes.mir.planner.technology_requirements")

local M = {}

function M.missing_reason(key, spec)
  for _, mod_name in ipairs(spec.required_mods or {}) do
    if not lookup.mod_exists(mod_name) then
      return "missing required mod " .. mod_name
    end
  end

  for _, item_name in ipairs(spec.required_items or {}) do
    if not lookup.item_prototype(item_name) then
      return "missing required item " .. item_name
    end
  end

  for _, fluid_name in ipairs(spec.required_fluids or {}) do
    if not lookup.fluid_prototype(fluid_name) then
      return "missing required fluid " .. fluid_name
    end
  end

  for _, tech_name in ipairs(spec.required_technologies or {}) do
    local reason = science.technology_researchability_reason(tech_name)
    if reason then
      return "unresearchable required technology " .. tech_name .. " (" .. reason .. ")"
    end
  end

  for _, candidates in ipairs(spec.required_technology_candidates or {}) do
    local found = false
    for _, tech_name in ipairs(candidates or {}) do
      if science.technology_is_researchable(tech_name) then
        found = true
        break
      end
    end
    if not found then
      return "no researchable required technology candidate " .. table.concat(candidates or {}, ",")
    end
  end

  local skip_reason = technology_requirements.skip_reason(spec)
  if skip_reason then return skip_reason end

  for _, category in ipairs(spec.required_ammo_categories or {}) do
    if not lookup.ammo_category_exists(category) then
      return "missing required ammo category " .. category
    end
  end

  return nil
end

return M
