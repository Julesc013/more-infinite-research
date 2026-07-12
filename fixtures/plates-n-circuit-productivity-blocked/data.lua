data:extend({
  {
    name = "basic-plate-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/advanced-material-processing.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      count_formula = "2500+2500*(L-1)",
      time = 30
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "copper-plate", change = 0.1},
      {type = "change-recipe-productivity", recipe = "iron-plate", change = 0.1}
    },
    prerequisites = {"advanced-material-processing"}
  },
  {
    name = "external-copper-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/advanced-material-processing.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      count_formula = "2500+2500*(L-1)",
      time = 30
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "copper-plate", change = 0.1}
    },
    prerequisites = {"advanced-material-processing"}
  }
})

data:extend({
  {
    type = "mod-data",
    name = "more-infinite-research-compatibility-pack",
    data = {
      packs = {
        ["plates-n-circuit-fixture"] = {
          schema = 2,
          id = "plates-n-circuit-fixture",
          applicability = {
            mods = {{id = "plates-n-circuit-productivity", version = "fixture"}}
          },
          aliases = {},
          exact = {includes = {}, excludes = {}},
          family_hints = {},
          science_roles = {},
          owner_claims = {
            known_competing_productivity = {
              tech_patterns = {
                "^basic%-plate%-productivity$",
                "^plate%-productivity$",
                "^electric%-circuit%-productivity$",
                "^electronic%-circuit%-productivity$",
                "^advanced%-circuit%-productivity$"
              }
            }
          },
          risk_overrides = {},
          targets = {factorio_lines = {"2.1"}},
          evidence = {
            fixtures = {"plates-n-circuit-productivity-blocked"},
            real_mod = {}
          },
          claim = {level = "fixture-only", public = false},
          expected_decisions = {"replace-exact-or-preserve-owner"}
        }
      }
    }
  }
})
