data:extend({
  {
    type = "recipe",
    name = "mir-fixture-adopt-rocket-fuel",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "solid-fuel", amount = 10}
    },
    results = {
      {type = "item", name = "rocket-fuel", amount = 1}
    },
    main_product = "rocket-fuel",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "recipe",
    name = "mir-fixture-adopt-low-density-structure",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "plastic-bar", amount = 5},
      {type = "item", name = "steel-plate", amount = 2}
    },
    results = {
      {type = "item", name = "low-density-structure", amount = 1}
    },
    main_product = "low-density-structure",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "recipe",
    name = "mir-fixture-adopt-plastic-bar",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "coal", amount = 1}
    },
    results = {
      {type = "item", name = "plastic-bar", amount = 2}
    },
    main_product = "plastic-bar",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "recipe",
    name = "mir-fixture-adopt-processing-unit",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "advanced-circuit", amount = 2},
      {type = "item", name = "electronic-circuit", amount = 20}
    },
    results = {
      {type = "item", name = "processing-unit", amount = 1}
    },
    main_product = "processing-unit",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "recipe",
    name = "mir-fixture-adopt-steel-plate",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "iron-plate", amount = 5}
    },
    results = {
      {type = "item", name = "steel-plate", amount = 1}
    },
    main_product = "steel-plate",
    allow_productivity = true,
    auto_recycle = false
  },
  {
    type = "recipe",
    name = "mir-fixture-no-productivity-rocket-fuel",
    categories = {"crafting"},
    enabled = false,
    ingredients = {
      {type = "item", name = "solid-fuel", amount = 5}
    },
    results = {
      {type = "item", name = "rocket-fuel", amount = 1}
    },
    main_product = "rocket-fuel",
    allow_productivity = false,
    auto_recycle = false
  }
})
