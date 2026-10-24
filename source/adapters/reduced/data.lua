-- Reduced targets deliberately do not install the modern Library shortcut.
local target = require("platform.target")

local M = {}

function M.apply()
  if target.reduced ~= true then error("MIR reduced data adapter requires a reduced target", 2) end
end

return M
