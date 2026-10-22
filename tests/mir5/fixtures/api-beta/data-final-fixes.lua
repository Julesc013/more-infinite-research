if not mods["more-infinite-research"] then return end

local api = require("__more-infinite-research__.api.v1.data")
if api.get_version().major ~= 1 or not api.get_capabilities().recipe_productivity then return end

api.add_productivity({
  type = "technology",
  name = "mir-api-fixture-beta-cable-1",
  prerequisites = {"electronics"},
  unit = {count = 50, ingredients = {{"automation-science-pack", 1}}, time = 20},
  effects = {}
}, {"copper-cable"}, 0.01)
