local api = require("__more-infinite-research__.api.v1.data")
assert(api.get_version().major == 1, "MIR API v1 is required")

local names = api.add_technologies({
  {
    type = "technology",
    name = "mir-api-fixture-alpha-1",
    prerequisites = {"mir-api-fixture-alpha-2"},
    unit = {count = 25, ingredients = {{"automation-science-pack", 1}}, time = 15},
    effects = {}
  },
  {
    type = "technology",
    name = "mir-api-fixture-alpha-2",
    prerequisites = {"automation"},
    unit = {count = 25, ingredients = {{"automation-science-pack", 1}}, time = 15},
    effects = {}
  }
})
assert(names[1] == "mir-api-fixture-alpha-1" and names[2] == "mir-api-fixture-alpha-2")
