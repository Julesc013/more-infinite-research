-- Py shares its authored Base bindings across F200 and the captured F210
-- HighTech route. Version hashes belong to the
-- evidence receipt; active selection is deliberately based on the relevant
-- providers and the named raw checks performed by the binding modules.
local target = require("platform.target")

local M = {}

local COAL_VISIBLE_SETTINGS = {
  research_material_py_acid_gas=true,
  research_material_py_glycerol=true,
  research_material_py_log=true,
  research_material_py_treated_wood=true,
  research_material_py_wood=true,
}

local HIGHTECH_VISIBLE_SETTINGS = {
  research_material_py_acid_gas=true,
  research_material_py_earth_flower_sample=true,
  research_material_py_earth_generic_sample=true,
  research_material_py_earth_jute_sample=true,
  research_material_py_earth_palmtree_sample=true,
  research_material_py_earth_potato_sample=true,
  research_material_py_earth_shroom_sample=true,
  research_material_py_earth_sunflower_sample=true,
  research_material_py_earth_tropical_tree_sample=true,
  research_material_py_earth_venus_fly_sample=true,
  research_material_py_glycerol=true,
  research_material_py_log=true,
  research_material_py_treated_wood=true,
  research_material_py_wood=true,
}

local function supported_base(active, hightech)
  local f200 = target.id == "f200" and target.factorio_version == "2.0"
  local f210 = target.id == "f210" and target.factorio_version == "2.1" and hightech
  if not f200 and not f210 or type(active) ~= "table" then return false end
  local label = f200 and "F200" or "F210"
  if active["space-age"] ~= nil then
    error("MIR unsupported " .. label .. " Py saved-profile transition: Space Age changes the captured science binding", 2)
  end
  if active.Krastorio2 ~= nil or active.Krastorio2Assets ~= nil
      or active["Krastorio2-spaced-out"] ~= nil or active["k2so-assets"] ~= nil then
    error("MIR unsupported " .. label .. " Py saved-profile transition: Krastorio changes the captured science binding", 2)
  end
  return true
end

function M.select(active)
  if type(active) ~= "table" then return {coal=false, hightech=false} end
  local coal = active.pycoalprocessing ~= nil
  local alienlife = active.pyalienlife ~= nil
  local hightech = active.pyhightech ~= nil
  if not coal and not hightech then return {coal=false, hightech=false} end
  if not supported_base(active, hightech) then return {coal=false, hightech=false} end
  if hightech and (not coal or not alienlife) then
    error("MIR unsupported " .. target.id:upper() .. " Py saved-profile transition: HighTech lacks the captured Coal Processing or AlienLife provider", 2)
  end
  if hightech then
    -- Py AlienLife changes log1 from the captured empty-input, automation
    -- owner route to a seedling/moss route. The HighTech capture emits only
    -- its three own rows; do not silently reuse the Py Coal log identity.
    return {coal=false, hightech=true}
  end
  if coal and alienlife then
    error("MIR unsupported F200 Py saved-profile transition: AlienLife changes the captured Py Coal log route", 2)
  end
  return {coal=coal, hightech=false}
end

function M.setting_visible(family, active)
  local selected = M.select(active)
  if selected.hightech then return HIGHTECH_VISIBLE_SETTINGS[family] == true end
  return selected.coal and COAL_VISIBLE_SETTINGS[family] == true
end

return M
