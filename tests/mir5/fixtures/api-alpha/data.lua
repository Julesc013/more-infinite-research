local api = require("__more-infinite-research__.api.v1.data")
assert(api.get_version().major == 1, "MIR API v1 is required")

local names = api.add_technologies({
  {
    type = "technology",
    name = "mir-api-fixture-alpha-1",
    icon = "__base__/graphics/technology/automation-1.png",
    icon_size = 256,
    prerequisites = {"mir-api-fixture-alpha-2"},
    unit = {count = 25, ingredients = {{"automation-science-pack", 1}}, time = 15},
    max_level = 1,
    effects = {{type = "character-crafting-speed", modifier = 0.05}}
  },
  {
    type = "technology",
    name = "mir-api-fixture-alpha-2",
    icon = "__base__/graphics/technology/automation-1.png",
    icon_size = 256,
    prerequisites = {"automation"},
    unit = {count = 25, ingredients = {{"automation-science-pack", 1}}, time = 15},
    effects = {}
  }
})
assert(names[1] == "mir-api-fixture-alpha-1" and names[2] == "mir-api-fixture-alpha-2")
