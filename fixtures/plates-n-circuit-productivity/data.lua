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
      {type = "change-recipe-productivity", recipe = "electronic-circuit", change = 0.1}
    },
    prerequisites = {"automation-2"}
  },
  {
    name = "advanced-circuit-productivity",
    type = "technology",
    icon = "__base__/graphics/technology/advanced-circuit.png",
    icon_size = 256,
    max_level = "infinite",
    unit = {
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      count_formula = "1000+1000*(L-1)",
      time = 60
    },
    effects = {
      {type = "change-recipe-productivity", recipe = "advanced-circuit", change = 0.1}
    },
    prerequisites = {"chemical-science-pack"}
  }
})

local prefix_owner = table.deepcopy(data.raw.technology["basic-plate-productivity"])
prefix_owner.name = "recipe-prod-external-prefix-owner"
prefix_owner.effects = {
  {type = "change-recipe-productivity", recipe = "iron-gear-wheel", change = 0.1}
}
prefix_owner.prerequisites = {"automation-2"}

local dependent = table.deepcopy(data.raw.technology["basic-plate-productivity"])
dependent.name = "mir-fixture-productivity-dependent"
dependent.max_level = nil
dependent.unit.count_formula = nil
dependent.unit.count = 100
dependent.effects = {}
dependent.prerequisites = {"basic-plate-productivity"}

data:extend({prefix_owner, dependent})

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
              {id = "mir-fixture-plates-n-circuit-productivity", version = "0.1.0"}
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
          targets = {factorio_lines = {"2.0", "2.1"}},
          evidence = {
            fixtures = {"plates-n-circuit-productivity"},
            real_mod = {}
          },
          claim = {level = "fixture-only", public = false},
          expected_decisions = {"replace-exact-or-preserve-owner"}
        }
      }
    }
  }
})
