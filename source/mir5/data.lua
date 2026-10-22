-- Data-stage entry for the private MIR5 Library slice.
local presentation = require("presentation.shortcut")

local has_space_age = mods ~= nil and mods["space-age"] ~= nil
data:extend({presentation.research_library_shortcut(has_space_age)})
