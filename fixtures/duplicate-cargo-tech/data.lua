local science = {
  {"science-pack-1", 1},
  {"science-pack-2", 1},
  {"science-pack-3", 1},
  {"alien-science-pack", 1}
}

data:extend({
  {
    type = "technology",
    name = "mir-fixture-duplicate-cargo-bay-unloading-distance",
    localised_name = {"technology-name.more-infinite-research.research_cargo_bay_unloading_distance"},
    icon = "__base__/graphics/technology/rocket-silo.png",
    icon_size = 256,
    effects = {
      {type = "max-cargo-bay-unloading-distance", modifier = 5}
    },
    prerequisites = {"landing-pad-unloading-bay"},
    unit = {
      count_formula = "1000 * 2^(L-1)",
      ingredients = science,
      time = 60
    },
    upgrade = true,
    max_level = "infinite",
    order = "z[mir-fixture-duplicate-cargo-bay-unloading-distance]"
  },
  {
    type = "technology",
    name = "mir-fixture-duplicate-cargo-landing-pad-count",
    localised_name = {"technology-name.more-infinite-research.research_cargo_landing_pad_count"},
    icon = "__base__/graphics/technology/rocket-silo.png",
    icon_size = 256,
    effects = {
      {type = "cargo-landing-pad-count", modifier = 1}
    },
    prerequisites = {"rocket-silo"},
    unit = {
      count_formula = "1000 * 2^(L-1)",
      ingredients = science,
      time = 60
    },
    upgrade = true,
    max_level = "infinite",
    order = "z[mir-fixture-duplicate-cargo-landing-pad-count]"
  }
})
