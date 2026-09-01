local M = {}
local target_line = require("prototypes.mir.platform.factorio.target_line")

local function assert_runtime_stage()
  if script == nil then
    error("MIR control.lua must run in Factorio's runtime Lua state", 2)
  end

  if type(_G) == "table" and rawget(_G, "data") ~= nil then
    error("MIR control.lua must not run in the prototype data stage", 2)
  end
end

function M.run()
  assert_runtime_stage()
  if target_line.feature_enabled("scripted_techs") or target_line.feature_enabled("productivity_family_adoption") then
    require("prototypes.mir.runtime.scripted_techs").register()
  end
  if target_line.feature_enabled("settings_profiles") then
    require("prototypes.mir.runtime.settings_profile").register()
  end
end

return M
