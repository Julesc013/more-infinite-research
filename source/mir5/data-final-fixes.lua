local configuration = require("research.settings")
local productivity = require("research.productivity")
local generator = require("research.generator")
generator.install({productivity.gears(configuration.resolve(settings.startup, helpers, log))}, data)
