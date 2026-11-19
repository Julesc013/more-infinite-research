-- Shared authored identities/bindings; safe for runtime metadata consumers.
-- Construction and prototype access stay in compatibility.material_catalogue.
return {
  {
    key="research_material_rare_metals",
    item="kr-rare-metals", icon="__Krastorio2Assets__/icons/items/rare-metals.png", icon_size=64,
    early={
      id="recipe-prod-research_material_rare_metals-1", max_level=3,
      order="p[research_material_rare_metals]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack",
        "kr-rare-metal-processing", "kr-enriched-ores"},
    },
    continuation={
      id="recipe-prod-research_material_rare_metals-4", first_level=4, max_level="infinite",
      predecessor_count=800, previous_count=400,
      order="p[research_material_rare_metals__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"recipe-prod-research_material_rare_metals-1", "space-science-pack"},
      show_levels_info=false, visible_when_disabled=true,
    },
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
    key="research_material_silicon",
    item="kr-silicon", icon="__Krastorio2Assets__/icons/items/silicon.png", icon_size=64,
    early={
      id="recipe-prod-research_material_silicon-1", max_level=3,
      order="p[research_material_silicon]", science={"automation-science-pack", "logistic-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "kr-silicon-processing"},
    },
    continuation={
      id="recipe-prod-research_material_silicon-4", first_level=4, max_level="infinite",
      predecessor_count=800, previous_count=400,
      order="p[research_material_silicon__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "space-science-pack"},
      prerequisites={"recipe-prod-research_material_silicon-1", "space-science-pack"},
      show_levels_info=false, visible_when_disabled=true,
    },
    routes={
      {recipe="kr-silicon", owner="kr-silicon-processing",
        ingredients={{type="item", name="kr-quartz", amount=18}},
        results={{type="item", name="kr-silicon", amount=9}}},
    },
  },
  {
    key="research_material_glass",
    item="kr-glass", icon="__Krastorio2Assets__/icons/items/glass.png", icon_size=64,
    early={
      id="recipe-prod-research_material_glass-1", max_level=3,
      order="p[research_material_glass]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack"},
      prerequisites={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "kr-stone-processing"},
    },
    continuation={
      id="recipe-prod-research_material_glass-4", first_level=4, max_level="infinite",
      predecessor_count=800, previous_count=400,
      order="p[research_material_glass__continuation]",
      science={"automation-science-pack", "logistic-science-pack", "chemical-science-pack", "space-science-pack"},
      prerequisites={"recipe-prod-research_material_glass-1", "space-science-pack"},
      show_levels_info=false, visible_when_disabled=true,
    },
    routes={
      {recipe="kr-glass", owner="kr-stone-processing",
        ingredients={{type="item", name="kr-sand", amount=16}},
        results={{type="item", name="kr-glass", amount=8}}},
    },
  },
}
