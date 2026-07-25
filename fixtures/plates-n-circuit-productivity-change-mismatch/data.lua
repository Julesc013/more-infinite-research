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
          schema = 2,
          id = "plates-n-circuit-fixture",
          applicability = {
            mods = {
              {id = "plates-n-circuit-productivity", version = "fixture"},
              {id = "mir-fixture-plates-n-circuit-productivity-change-mismatch", version = "0.1.0"}
            }
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
          family_authorizations = {},
          candidate_seeds = {},
          targets = {factorio_lines = {"2.1"}},
          evidence = {
            fixtures = {"plates-n-circuit-productivity-change-mismatch"},
            real_mod = {}
          },
          claim = {level = "fixture-only", public = false},
          expected_decisions = {"replace-exact-or-preserve-owner"}
        }
      }
    }
  }
})
