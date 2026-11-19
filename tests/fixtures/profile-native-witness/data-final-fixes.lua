local witness = require("witness")
local actual = witness.data(data.raw, mods.base, settings.startup["profile-native-witness-mode"].value)
log(witness.line(actual))
