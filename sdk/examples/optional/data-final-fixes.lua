-- `mods` is available in data stages. Expected absence is handled before
-- importing the optional public dependency.
if not mods["more-infinite-research"] then return end
local api = require("__more-infinite-research__.api.v1.data")
if api.get_version().major ~= 1 then return end
if not api.get_capabilities().recipe_productivity then return end
api.add_productivity({
  type = "technology",
  name = "mir-api-example-optional-cable-1",
  prerequisites = {"automation"},
  unit = {
    count = 100,
    ingredients = {{"automation-science-pack", 1}},
    time = 30
  }
}, {"copper-cable"}, 0.01)
