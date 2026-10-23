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
local technologies = {gear}

-- The two scripted streams have no base fallback. Require both their exact
-- bindings and authoring body only after Space Age is active.
if type(mods) == "table" and mods["space-age"] ~= nil
    and values.agricultural_growth_speed ~= nil and values.spoilage_preservation ~= nil then
  local bindings = require("compatibility.space_age_scripted_effects").select(mods, data.raw)
  local scripted = require("research.scripted_effects").technologies(values, bindings)
  technologies[#technologies + 1] = scripted[1]
  technologies[#technologies + 1] = scripted[2]
end

generator.install(technologies, data)

-- The published experimental override is unavailable by default.  Keeping its
-- require in this strict branch means disabled data stages never load or inspect it.
if values.unrestricted_modules == true then
  require("overrides.module_permissions").apply(data.raw, true)
end
