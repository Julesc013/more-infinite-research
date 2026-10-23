local configuration = require("research.settings")
local values = configuration.resolve(settings.startup, helpers, log)
local productivity = require("research.productivity")
local generator = require("research.generator")

local gear
if values.enabled == true then
  -- Disabled continuity keeps the owned identity but does not load or inspect
  -- an active profile binding. Active bindings preflight named recipes here.
  local binding = require("compatibility.gear_bindings").select(mods, data.raw)
  gear = productivity.gears(values, binding)
else
  gear = productivity.gears(values)
end
generator.install({gear}, data)

-- The published experimental override is unavailable by default.  Keeping its
-- require in this strict branch means disabled data stages never load or inspect it.
if values.unrestricted_modules == true then
  require("overrides.module_permissions").apply(data.raw, true)
end
