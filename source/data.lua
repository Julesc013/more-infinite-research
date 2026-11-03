-- Data-stage entry for the private MIR5 Library slice.
local presentation = require("presentation.shortcut")

local has_space_age = mods ~= nil and mods["space-age"] ~= nil
local prototypes = {presentation.research_library_shortcut(has_space_age)}
local target = require("platform.target")
if has_space_age and (target.id == "f200" or target.id == "f210") then
  prototypes[#prototypes + 1] = require("research.native_adoption").prototype()
end
data:extend(prototypes)
