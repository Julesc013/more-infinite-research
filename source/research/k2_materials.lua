-- Shared authored identities/bindings; safe for runtime metadata consumers.
-- Construction and prototype access stay in compatibility.material_catalogue.
return {
  {
    key="research_material_rare_metals", name="recipe-prod-research_material_rare_metals-1",
    item="kr-rare-metals", icon="__Krastorio2Assets__/icons/items/rare-metals.png",
    order="p[research_material_rare_metals]",
    science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
    prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
      "kr-rare-metal-processing", "kr-enriched-ores"},
    routes={
      {recipe="kr-rare-metals", owner="kr-rare-metal-processing",
        ingredients={{type="item", name="kr-rare-metal-ore", amount=2}},
        results={{type="item", name="kr-rare-metals", amount=1}}},
      {recipe="kr-rare-metals-from-enriched-rare-metals", owner="kr-enriched-ores",
        ingredients={{type="item", name="kr-enriched-rare-metals", amount=1}},
        results={{type="item", name="kr-rare-metals", amount=1}}},
    },
  },
  {
    key="research_material_silicon", name="recipe-prod-research_material_silicon-1",
    item="kr-silicon", icon="__Krastorio2Assets__/icons/items/silicon.png",
    order="p[research_material_silicon]", science={"automation-science-pack", "logistic-science-pack"},
    prerequisites={"automation-science-pack", "logistic-science-pack", "kr-silicon-processing"},
    routes={
      {recipe="kr-silicon", owner="kr-silicon-processing",
        ingredients={{type="item", name="kr-quartz", amount=18}},
        results={{type="item", name="kr-silicon", amount=9}}},
    },
  },
  {
    key="research_material_glass", name="recipe-prod-research_material_glass-1",
    item="kr-glass", icon="__Krastorio2Assets__/icons/items/glass.png",
    order="p[research_material_glass]",
    science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
    prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "kr-stone-processing"},
    routes={
      {recipe="kr-glass", owner="kr-stone-processing",
        ingredients={{type="item", name="kr-sand", amount=16}},
        results={{type="item", name="kr-glass", amount=8}}},
    },
  },
}
