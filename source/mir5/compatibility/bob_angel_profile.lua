-- The captured F200 no-BobTech variant, shared by data/settings/runtime.
-- This selects authored bindings; it never reads prototypes or saved state.
local target = require("platform.target")
local M = {}
local REQUIRED = {
  base="2.0.77", angelsbioprocessing="2.0.3", angelsbioprocessinggraphics="2.0.0",
  angelspetrochem="2.0.3", angelspetrochemgraphics="2.0.1",
  angelsrefining="2.0.4", angelsrefininggraphics="2.0.0",
  angelssmelting="2.0.5", angelssmeltinggraphics="2.0.0",
  bobelectronics="2.1.1", boblibrary="2.1.0", bobores="2.1.2",
  bobplates="2.1.1", bobrevamp="2.1.1",
}

function M.applies(active)
  if target.id ~= "f200" or target.factorio_version ~= "2.0" or type(active) ~= "table"
    or active["space-age"] ~= nil or active.bobtech ~= nil
    or active.Krastorio2 ~= nil or active["Krastorio2-spaced-out"] ~= nil then return false end
  for name, version in pairs(REQUIRED) do if active[name] ~= version then return false end end
  return true
end

local VISIBLE = {}
for _, suffix in ipairs({"aluminium", "brass", "bronze", "cobalt_steel", "copper_tungsten",
  "glycerol", "gold", "gunmetal", "hydrochloric_acid", "hydrofluoric_acid", "invar",
  "lead", "nickel", "nitinol", "nitric_acid", "platinum", "silver", "tin", "titanium", "zinc"}) do
  VISIBLE["research_material_" .. suffix] = true
end
function M.setting_visible(family) return VISIBLE[family] == true end

return M
