-- `mods` is available in data stages. Expected absence is handled before
-- importing the optional public dependency.
if not mods["more-infinite-research"] then return end
local api = require("__more-infinite-research__.api.v1.data")
if api.get_version().major ~= 1 then return end
if not api.get_capabilities().recipe_productivity then return end
api.add_productivity({
  type = "technology",
  name = "mir-api-example-optional-cable-1",
  icon = "__base__/graphics/technology/automation.png",
  icon_size = 256,
  prerequisites = {"automation"},
  unit = {
    count_formula = "100 * 2^(L-1)",
    ingredients = {{"automation-science-pack", 1}},
    time = 30
  },
  max_level = "infinite",
  upgrade = true
}, {"copper-cable"}, 0.01)
