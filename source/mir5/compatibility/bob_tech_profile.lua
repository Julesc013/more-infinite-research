-- Exact F210 BobTech plus Angel Smelting tuple that published the retained
-- Tin, Gunmetal, and Invar material identities.  This module deliberately
-- reads only the selected target and relevant mod versions; recipe and owner
-- conformance belongs to the data-stage binding module.
local target = require("platform.target")

local M = {}

local REQUIRED = {
  base = "2.1.23",
  ["space-age"] = "2.1.23",
  boblibrary = "3.0.1",
  bobores = "3.0.0",
  bobplates = "3.0.2",
  bobelectronics = "3.0.1",
  bobtech = "3.0.0",
  angelsrefining = "2.1.2",
  angelsrefininggraphics = "2.1.0",
  angelspetrochem = "2.1.3",
  angelspetrochemgraphics = "2.1.0",
  angelssmelting = "2.1.1",
  angelssmeltinggraphics = "2.1.1",
}

local VISIBLE = {
  research_material_tin = true,
  research_material_gunmetal = true,
  research_material_invar = true,
}

local function complete_closure(active)
  for name in pairs(REQUIRED) do
    if active[name] == nil then return false end
  end
  return true
end

local function fail_transition(reason)
  error("MIR unsupported F210 BobTech saved-profile transition: " .. reason, 2)
end

function M.applies(active)
  if target.id ~= "f210" or target.factorio_version ~= "2.1" or type(active) ~= "table" then return false end
  -- A partial closure could be a fresh, unrelated mod selection. A complete
  -- named predecessor with a changed member could instead carry these five
  -- already-saved identities, so it must block before data-stage omission.
  if not complete_closure(active) then return false end
  -- Target records may raise their declared minimum for an official patch.
  -- That is not evidence that this F210 predecessor can be omitted.
  if target.minimum_base ~= "2.1.23" then
    fail_transition("target minimum base is " .. tostring(target.minimum_base) .. ", expected 2.1.23")
  end
  if active.Krastorio2 ~= nil or active.Krastorio2Assets ~= nil
      or active["Krastorio2-spaced-out"] ~= nil or active["k2so-assets"] ~= nil then
    fail_transition("captured BobTech closure has an unsupported Krastorio selection")
  end
  for name, version in pairs(REQUIRED) do
    if active[name] ~= version then
      fail_transition(name .. " is " .. tostring(active[name]) .. ", expected " .. version)
    end
  end
  return true
end

function M.setting_visible(family)
  return VISIBLE[family] == true
end

return M
