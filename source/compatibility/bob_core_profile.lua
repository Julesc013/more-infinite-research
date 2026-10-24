-- Exact F210 Bob Core closure from the independent no-Angel capture.  This
-- gate selects one finite authored binding; it never inspects prototypes.
local target = require("platform.target")

local M = {}

local REQUIRED = {
  "base", "space-age", "boblibrary", "bobores", "bobplates", "bobelectronics", "bobtech",
}

local ANGEL = {
  "angelsbioprocessing", "angelsbioprocessinggraphics", "angelsrefining", "angelsrefininggraphics",
  "angelspetrochem", "angelspetrochemgraphics", "angelssmelting", "angelssmeltinggraphics",
}

local UNSUPPORTED = {
  "Krastorio2", "Krastorio2Assets", "Krastorio2-spaced-out", "k2so-assets",
  "pycoalprocessing", "pyalienlife", "pyhightech",
}

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

local function complete_closure(active)
  for _, name in ipairs(REQUIRED) do
    if active[name] == nil then return false end
  end
  return true
end

local function any_active(active, names)
  for _, name in ipairs(names) do
    if active[name] ~= nil then return true end
  end
  return false
end

function M.applies(active)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or type(active) ~= "table" then return false end
  if not complete_closure(active) then return false end
  -- Angel has its own named F210 binding and is an ordinary non-selection for
  -- this no-Angel profile, rather than an error from a competing adapter.
  if any_active(active, ANGEL) then return false end
  if target.minimum_base ~= "2.1.23" then
    error("MIR unsupported F210 Bob Core saved-profile transition: target minimum base is "
      .. tostring(target.minimum_base) .. ", expected 2.1.23", 2)
  end
  if any_active(active, UNSUPPORTED) then
    error("MIR unsupported F210 Bob Core saved-profile transition: captured closure has an unsupported overhaul selection", 2)
  end
  return true
end

function M.setting_visible(family)
  return VISIBLE[family] == true
end

return M
