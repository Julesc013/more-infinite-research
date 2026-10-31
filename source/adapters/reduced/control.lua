-- Reduced targets expose the same bounded runtime API without Library or
-- scripted-effect event maintenance.
local target = require("platform.target")
local runtime_api = require("api.v1.runtime")

local M = {}
local INTERFACE = "more-infinite-research.api.v1"

function M.apply()
  if target.reduced ~= true then error("MIR reduced control adapter requires a reduced target", 2) end
  local current_remote = rawget(_G, "remote")
  if current_remote == nil then
    error("MIR reduced control adapter requires remote.add_interface", 2)
  end
  local readable_interfaces, interfaces = pcall(function() return current_remote.interfaces end)
  if not readable_interfaces or interfaces == nil then
    error("MIR reduced control adapter requires readable remote.interfaces", 2)
  end
  local readable_existing, existing = pcall(function() return interfaces[INTERFACE] end)
  if not readable_existing then
    error("MIR reduced control adapter requires readable remote.interfaces", 2)
  end
  if existing ~= nil then
    error("MIR API interface already exists: " .. INTERFACE, 2)
  end
  local readable_register, register = pcall(function() return current_remote.add_interface end)
  if not readable_register or register == nil then
    error("MIR reduced control adapter requires remote.add_interface", 2)
  end
  local registered, message = pcall(register, INTERFACE, {
    get_version=runtime_api.get_version,
    get_capabilities=runtime_api.get_capabilities,
    get_research=runtime_api.get_research,
  })
  if not registered then error("MIR reduced control adapter could not register API: " .. tostring(message), 2) end
end

return M
