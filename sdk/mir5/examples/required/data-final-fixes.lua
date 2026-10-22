-- Candidate API example, not native-qualified. This is an independent test mod.
local api = require("__more-infinite-research__.api.v1.data")
assert(api.get_version().major == 1, "Expected MIR API 1")
assert(api.get_capabilities().recipe_productivity, "Recipe productivity unavailable")
api.add_productivity({
  type = "technology",
  name = "mir-api-example-required-gears-1",
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
}, {"iron-gear-wheel"}, 0.01)
