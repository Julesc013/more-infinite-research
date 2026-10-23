local configuration = require("research.settings")
local values = configuration.resolve(settings.startup, helpers, log)
local productivity = require("research.productivity")
local generator = require("research.generator")

generator.install({productivity.gears(values)}, data)

-- The published experimental override is unavailable by default.  Keeping its
-- require in this strict branch means disabled data stages never load or inspect it.
if values.unrestricted_modules == true then
  require("overrides.module_permissions").apply(data.raw, true)
end
