-- The captured F200 no-BobTech variant, shared by data/settings/runtime.
-- This selects authored bindings; it never reads prototypes or saved state.
local target = require("platform.target")
local M = {}
local REQUIRED = {
  "base", "angelsbioprocessing", "angelsbioprocessinggraphics", "angelspetrochem", "angelspetrochemgraphics",
  "angelsrefining", "angelsrefininggraphics", "angelssmelting", "angelssmeltinggraphics",
  "bobelectronics", "boblibrary", "bobores", "bobplates", "bobrevamp",
}

local function complete_closure(active)
  for _, name in ipairs(REQUIRED) do
    if active[name] == nil then return false end
  end
  return true
end

local function fail_transition(reason)
  error("MIR unsupported F200 Bob/Angel saved-profile transition: " .. reason, 2)
end

function M.applies(active)
  if target.id ~= "f200" or target.factorio_version ~= "2.0" or type(active) ~= "table" then return false end
  -- The material constructor verifies named routes directly. Known mixed
  -- Space Age, BobTech, and Krastorio profiles remain excluded here.
  if not complete_closure(active) then return false end
  if active["space-age"] ~= nil or active.bobtech ~= nil
    or active.Krastorio2 ~= nil or active["Krastorio2-spaced-out"] ~= nil then
    fail_transition("captured Bob/Angel closure has an unsupported Space Age, BobTech, or Krastorio selection")
  end
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
