-- Reduced targets deliberately do not install the modern Library shortcut.
local startup_trace = require("startup_diagnostics").start("data")
local target = require("platform.target")

local M = {}

function M.apply()
  if target.reduced ~= true then error("MIR reduced data adapter requires a reduced target", 2) end
  startup_trace.phase("stage", "end")
end

return M
