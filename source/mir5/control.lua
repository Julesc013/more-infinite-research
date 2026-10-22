-- Parse-time composition only.  Event handlers and remote calls use the
-- modules imported here; no runtime handler imports the Generator.
local lifecycle = require("runtime.lifecycle")
local runtime_api = require("api.v1.runtime")

local INTERFACE = "more-infinite-research.api.v1"

if remote.interfaces[INTERFACE] ~= nil then
  error("MIR API interface collision: " .. INTERFACE)
end

remote.add_interface(INTERFACE, {
  get_version = runtime_api.get_version,
  get_capabilities = runtime_api.get_capabilities,
  get_research = runtime_api.get_research
})

lifecycle.register()
