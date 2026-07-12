data:extend({
  {
    name = "electric-circuit-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/electronics.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      count_formula = "1000+1000*(L-1)",
      time = 30
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "electronic-circuit", change = 0.05}
    },
    prerequisites = {"automation-2"}
  }
})

data:extend({
  {
    type = "mod-data",
    name = "more-infinite-research-compatibility-pack",
    data = {
      packs = {
        ["plates-n-circuit-fixture"] = {
          schema = 1,
          id = "plates-n-circuit-fixture",
          known_competing_productivity = {
            tech_patterns = {
              "^basic%-plate%-productivity$",
              "^plate%-productivity$",
              "^electric%-circuit%-productivity$",
              "^electronic%-circuit%-productivity$",
              "^advanced%-circuit%-productivity$"
            }
          },
          expected_decisions = {"replace-exact-or-preserve-owner"},
          claim_level = "fixture-only"
        }
      }
    }
  }
})
