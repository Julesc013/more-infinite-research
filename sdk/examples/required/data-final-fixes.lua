-- Required public API draft example. This call publishes immediately in this
-- consumer's final-fixes stage; it does not wait for an MIR finalizer.
local api = require("__more-infinite-research__.api.v1.data")
assert(api.get_version().major == 1, "Expected MIR API 1")
assert(api.get_capabilities().recipe_productivity, "Recipe productivity unavailable")
api.add_productivity({
  type = "technology",
  name = "mir-api-example-required-gears-1",
  prerequisites = {"automation"},
  unit = {
    count = 100,
    ingredients = {{"automation-science-pack", 1}},
    time = 30
  }
}, {"iron-gear-wheel"}, 0.01)
