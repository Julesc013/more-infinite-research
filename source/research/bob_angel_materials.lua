-- Fixed F200 Bob/Angel material identities and their named native routes.
-- This is data only: it does not scan prototypes, derive routes, or select an
-- owner. The separate compatibility constructor validates these exact
-- published-F200 bindings before constructing fresh MIR-owned technologies.
-- `maximum_productivity = "omitted"` pins captured raw field absence; a
-- numeric value would be an explicit captured recipe cap. Each family
-- declares the engine-default 300% productivity ceiling for runtime policy.

return {
  {
    key = "research_material_aluminium",
    productivity_ceiling = 3,
    item = "bob-aluminium-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-aluminium.png",
    icon_size = 32,
    routes = {
      {
        recipe = "angels-plate-aluminium",
        maximum_productivity = "omitted",
        owner = "angels-aluminium-smelting-1",
        ingredients = {
          {
            type = "fluid",
            name = "angels-liquid-molten-aluminium",
            amount = 40,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-aluminium-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-ore-floatation",
          "angels-powder-metallurgy-2",
          "angels-chlorine-processing-1",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
        },
      },
      {
        recipe = "angels-plate-aluminium-2",
        maximum_productivity = "omitted",
        owner = "angels-aluminium-casting-2",
        ingredients = {
          {
            type = "item",
            name = "angels-roll-aluminium",
            amount = 1,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-aluminium-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-strand-casting-2",
          "angels-aluminium-smelting-1",
          "angels-manganese-smelting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_aluminium-1",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "angels-aluminium-smelting-1",
        "angels-aluminium-casting-2",
      },
      max_level = 3,
      order = "p[research_material_aluminium]",
    },
    continuation = {
      id = "recipe-prod-research_material_aluminium-4",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
        "utility-science-pack",
      },
      prerequisites = {
        "angels-aluminium-casting-2",
        "angels-aluminium-smelting-1",
        "automation-science-pack",
        "logistic-science-pack",
        "recipe-prod-research_material_aluminium-1",
        "utility-science-pack",
      },
      max_level = "infinite",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      order = "p[research_material_aluminium__continuation]",
    },
  },
  {
    key = "research_material_copper_tungsten",
    productivity_ceiling = 3,
    item = "bob-copper-tungsten-alloy",
    icon = "__bobplates__/graphics/icons/plate/copper-tungsten-plate.png",
    icon_size = 32,
    routes = {
      {
        recipe = "bob-copper-tungsten-alloy",
        maximum_productivity = "omitted",
        owner = "angels-tungsten-smelting-1",
        ingredients = {
          {
            type = "item",
            name = "bob-powdered-tungsten",
            amount = 15,
          },
          {
            type = "item",
            name = "angels-powder-copper",
            amount = 10,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-copper-tungsten-alloy",
            amount = 25,
          },
        },
        owner_prerequisites = {
          "angels-ore-refining",
          "angels-powder-metallurgy-4",
          "angels-cobalt-smelting-2",
          "angels-chlorine-processing-2",
          "angels-sulfur-processing-2",
          "angels-copper-smelting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "production-science-pack",
            amount = 1,
          },
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_copper_tungsten-1",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "angels-tungsten-smelting-1",
      },
      max_level = 3,
      order = "p[research_material_copper_tungsten]",
    },
    continuation = {
      id = "recipe-prod-research_material_copper_tungsten-4",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
        "utility-science-pack",
      },
      prerequisites = {
        "angels-tungsten-smelting-1",
        "automation-science-pack",
        "logistic-science-pack",
        "recipe-prod-research_material_copper_tungsten-1",
        "utility-science-pack",
      },
      max_level = "infinite",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      order = "p[research_material_copper_tungsten__continuation]",
    },
  },
  {
    key = "research_material_gold",
    productivity_ceiling = 3,
    item = "bob-gold-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-gold.png",
    icon_size = 32,
    routes = {
      {
        recipe = "angels-plate-gold",
        maximum_productivity = "omitted",
        owner = "angels-gold-smelting-1",
        ingredients = {
          {
            type = "fluid",
            name = "angels-liquid-molten-gold",
            amount = 40,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-gold-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-ore-leaching",
          "angels-metallurgy-3",
          "angels-chlorine-processing-1",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
        },
      },
      {
        recipe = "angels-plate-gold-2",
        maximum_productivity = "omitted",
        owner = "angels-gold-casting-2",
        ingredients = {
          {
            type = "item",
            name = "angels-roll-gold",
            amount = 1,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-gold-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-strand-casting-3",
          "angels-gold-smelting-1",
          "angels-copper-casting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "production-science-pack",
            amount = 1,
          },
        },
      },
      {
        recipe = "angels-wire-gold-2",
        maximum_productivity = "omitted",
        owner = "angels-gold-casting-2",
        ingredients = {
          {
            type = "item",
            name = "angels-wire-coil-gold",
            amount = 4,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-gilded-copper-cable",
            amount = 16,
          },
        },
        owner_prerequisites = {
          "angels-strand-casting-3",
          "angels-gold-smelting-1",
          "angels-copper-casting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "production-science-pack",
            amount = 1,
          },
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_gold-1",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "angels-gold-smelting-1",
        "angels-gold-casting-2",
      },
      max_level = 3,
      order = "p[research_material_gold]",
    },
    continuation = {
      id = "recipe-prod-research_material_gold-4",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
        "utility-science-pack",
      },
      prerequisites = {
        "angels-gold-casting-2",
        "angels-gold-smelting-1",
        "automation-science-pack",
        "logistic-science-pack",
        "recipe-prod-research_material_gold-1",
        "utility-science-pack",
      },
      max_level = "infinite",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      order = "p[research_material_gold__continuation]",
    },
  },
  {
    key = "research_material_tin",
    productivity_ceiling = 3,
    item = "bob-tin-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-tin.png",
    icon_size = 32,
    routes = {
      {
        recipe = "angels-plate-tin",
        maximum_productivity = "omitted",
        owner = "angels-tin-smelting-1",
        ingredients = {
          {
            type = "fluid",
            name = "angels-liquid-molten-tin",
            amount = 40,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-tin-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-metallurgy-1",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
        },
      },
      {
        recipe = "angels-plate-tin-2",
        maximum_productivity = "omitted",
        owner = "angels-tin-casting-2",
        ingredients = {
          {
            type = "item",
            name = "angels-roll-tin",
            amount = 1,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-tin-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-strand-casting-1",
          "angels-tin-smelting-1",
          "angels-copper-casting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_tin-1",
      science = {
        "automation-science-pack",
      },
      prerequisites = {
        "automation-science-pack",
        "angels-tin-smelting-1",
        "angels-tin-casting-2",
      },
      max_level = 3,
      order = "p[research_material_tin]",
    },
    continuation = {
      id = "recipe-prod-research_material_tin-4",
      science = {
        "automation-science-pack",
        "utility-science-pack",
      },
      prerequisites = {
        "angels-tin-casting-2",
        "angels-tin-smelting-1",
        "automation-science-pack",
        "recipe-prod-research_material_tin-1",
        "utility-science-pack",
      },
      max_level = "infinite",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      order = "p[research_material_tin__continuation]",
    },
  },
  {
    key = "research_material_titanium",
    productivity_ceiling = 3,
    item = "bob-titanium-plate",
    icon = "__angelssmeltinggraphics__/graphics/icons/plate-titanium.png",
    icon_size = 32,
    routes = {
      {
        recipe = "angels-plate-titanium",
        maximum_productivity = "omitted",
        owner = "angels-titanium-smelting-1",
        ingredients = {
          {
            type = "fluid",
            name = "angels-liquid-molten-titanium",
            amount = 40,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-titanium-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-ore-leaching",
          "angels-metallurgy-3",
          "angels-coal-processing-2",
          "angels-chlorine-processing-1",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
        },
      },
      {
        recipe = "angels-plate-titanium-2",
        maximum_productivity = "omitted",
        owner = "angels-titanium-casting-2",
        ingredients = {
          {
            type = "item",
            name = "angels-roll-titanium",
            amount = 1,
          },
        },
        results = {
          {
            type = "item",
            name = "bob-titanium-plate",
            amount = 4,
          },
        },
        owner_prerequisites = {
          "angels-strand-casting-3",
          "angels-titanium-smelting-1",
          "angels-manganese-smelting-3",
          "angels-nickel-smelting-2",
        },
        owner_science = {
          {
            type = "item",
            name = "automation-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "logistic-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "chemical-science-pack",
            amount = 1,
          },
          {
            type = "item",
            name = "production-science-pack",
            amount = 1,
          },
        },
      },
    },
    early = {
      id = "recipe-prod-research_material_titanium-1",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
      },
      prerequisites = {
        "automation-science-pack",
        "logistic-science-pack",
        "angels-titanium-smelting-1",
        "angels-titanium-casting-2",
      },
      max_level = 3,
      order = "p[research_material_titanium]",
    },
    continuation = {
      id = "recipe-prod-research_material_titanium-4",
      science = {
        "automation-science-pack",
        "logistic-science-pack",
        "utility-science-pack",
      },
      prerequisites = {
        "angels-titanium-casting-2",
        "angels-titanium-smelting-1",
        "automation-science-pack",
        "logistic-science-pack",
        "recipe-prod-research_material_titanium-1",
        "utility-science-pack",
      },
      max_level = "infinite",
      first_level = 4,
      predecessor_count = 800,
      previous_count = 400,
      order = "p[research_material_titanium__continuation]",
    },
  },
}
