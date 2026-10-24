-- Data-only F210 BobTech material contract.  These are the five published
-- technology rows for the exact BobTech plus Angel Smelting tuple: Tin's
-- finite stage and Gunmetal/Invar's finite plus level-four continuations.
-- Tin has no continuation here because the published tuple withheld it for
-- lack of a reachable late-science frontier.
return {
  {
    key = "research_material_tin",
    item = "bob-tin-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-tin.png",
    icon_size = 32,
    productivity_ceiling = 3,
    routes = {
      {
        recipe = "angels-plate-tin",
        owner = "angels-tin-smelting-1",
        maximum_productivity = 3,
        ingredients = {{type="fluid", name="angels-liquid-molten-tin", amount=40}},
        results = {{type="item", name="bob-tin-plate", amount=4}},
        owner_prerequisites = {"angels-metallurgy-1"},
        owner_science = {{type="item", name="automation-science-pack", amount=1}},
      },
      {
        recipe = "angels-plate-tin-2",
        owner = "angels-tin-casting-2",
        maximum_productivity = 3,
        ingredients = {{type="item", name="angels-roll-tin", amount=1}},
        results = {{type="item", name="bob-tin-plate", amount=4}},
        owner_prerequisites = {"angels-strand-casting-1", "angels-tin-smelting-1", "angels-copper-casting-2"},
        owner_science = {
          {type="item", name="automation-science-pack", amount=1},
          {type="item", name="logistic-science-pack", amount=1},
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_tin-1",
      max_level = 3,
      order = "p[research_material_tin]",
      science = {"automation-science-pack"},
      prerequisites = {"automation-science-pack", "angels-tin-smelting-1", "angels-tin-casting-2"},
    },
  },
  {
    key = "research_material_gunmetal",
    item = "bob-gunmetal-alloy",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-gunmetal.png",
    icon_size = 32,
    productivity_ceiling = 3,
    routes = {
      {
        recipe = "angels-plate-gunmetal",
        owner = "angels-gunmetal-smelting-1",
        maximum_productivity = 3,
        ingredients = {{type="fluid", name="angels-liquid-molten-gunmetal", amount=40}},
        results = {{type="item", name="bob-gunmetal-alloy", amount=4}},
        owner_prerequisites = {"angels-tin-smelting-1", "angels-zinc-smelting-1", "angels-copper-smelting-1"},
        owner_science = {
          {type="item", name="automation-science-pack", amount=1},
          {type="item", name="logistic-science-pack", amount=1},
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_gunmetal-1",
      max_level = 3,
      order = "p[research_material_gunmetal]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"angels-gunmetal-smelting-1", "automation-science-pack", "logistic-science-pack"},
    },
    continuation = {
      id = "recipe-prod-research_material_gunmetal-4",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      max_level = "infinite",
      order = "p[research_material_gunmetal__continuation]",
      show_levels_info = false,
      visible_when_disabled = true,
      science = {"automation-science-pack", "logistic-science-pack", "space-science-pack"},
      prerequisites = {
        "angels-gunmetal-smelting-1", "automation-science-pack", "logistic-science-pack",
        "space-science-pack", "recipe-prod-research_material_gunmetal-1",
      },
    },
  },
  {
    key = "research_material_invar",
    item = "bob-invar-alloy",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-invar.png",
    icon_size = 32,
    productivity_ceiling = 3,
    routes = {
      {
        recipe = "angels-plate-invar",
        owner = "angels-invar-smelting-1",
        maximum_productivity = 3,
        ingredients = {{type="fluid", name="angels-liquid-molten-invar", amount=40}},
        results = {{type="item", name="bob-invar-alloy", amount=4}},
        owner_prerequisites = {"angels-steel-smelting-1", "angels-nickel-smelting-1"},
        owner_science = {
          {type="item", name="automation-science-pack", amount=1},
          {type="item", name="logistic-science-pack", amount=1},
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_invar-1",
      max_level = 3,
      order = "p[research_material_invar]",
      science = {"automation-science-pack", "logistic-science-pack"},
      prerequisites = {"angels-invar-smelting-1", "automation-science-pack", "logistic-science-pack"},
    },
    continuation = {
      id = "recipe-prod-research_material_invar-4",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      max_level = "infinite",
      order = "p[research_material_invar__continuation]",
      show_levels_info = false,
      visible_when_disabled = true,
      science = {"automation-science-pack", "logistic-science-pack", "space-science-pack"},
      prerequisites = {
        "angels-invar-smelting-1", "automation-science-pack", "logistic-science-pack",
        "space-science-pack", "recipe-prod-research_material_invar-1",
      },
    },
  },
}
