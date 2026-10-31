-- One parse-time resolution for the runtime owners. Startup values cannot
-- change within a loaded control instance; remote exports resolve on request.
local catalogue = require("research.settings")
local function report(message)
  if type(log) == "function" then log(message) end
end
return catalogue.resolve(settings.startup, helpers, report)
