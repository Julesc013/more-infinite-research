local M = {}

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
  require("control.scripted-techs").register()
end

return M
