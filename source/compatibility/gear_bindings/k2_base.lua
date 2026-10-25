-- Exact retained F200 and independently captured F210 K2 core bindings.
-- Alternative K2 gear recipes remain with the shared product collector after
-- this named seed route; this map never substitutes the K2SO tuple.
local target = require("platform.target")

local profiles = {f200 = "k2-base-f200", f210 = "k2-base-f210"}
local profile = profiles[target.id]
if profile == nil then error("MIR K2 Base gear binding has no admitted target", 2) end

return {
  profile = profile,
  icon = "__Krastorio2Assets__/icons/items/iron-gear-wheel.png",
  recipes = {"iron-gear-wheel"}
}
