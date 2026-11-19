-- Exact F210 Bob Core closure from the independent no-Angel capture.  This
-- gate selects one finite authored binding; it never inspects prototypes.
local target = require("platform.target")
local selection = require("compatibility.bob_core_selection")

local M = {}

local VISIBLE = {
  research_material_aluminium = true,
  research_material_brass = true,
  research_material_bronze = true,
  research_material_cobalt_steel = true,
  research_material_copper_tungsten = true,
  research_material_gold = true,
  research_material_gunmetal = true,
  research_material_invar = true,
  research_material_lead = true,
  research_material_nickel = true,
  research_material_nitinol = true,
  research_material_platinum = true,
  research_material_silver = true,
  research_material_tin = true,
  research_material_titanium = true,
  research_material_zinc = true,
}

function M.applies(active)
  local status = selection.status(active, target)
  if status == "unsupported-overhaul" then
    error("MIR unsupported F210 Bob Core saved-profile transition: captured closure has an unsupported overhaul selection", 2)
  end
  return status == "selected"
end

function M.setting_visible(family)
  return VISIBLE[family] == true
end

return M
