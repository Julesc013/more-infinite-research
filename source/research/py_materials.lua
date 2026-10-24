-- Exact F200 Py Coal material authoring.  Wood and treated wood remain
-- withheld: this file names only the two published log stages.
return {
  {
    key="research_material_py_log",
    item="log",
    icon="__pycoalprocessinggraphics__/graphics/icons/mip/log-01.png",
    icon_size=64,
    routes={{
      recipe="log1", owner="wood-processing", maximum_productivity=1000000,
      ingredients={}, results={{type="item",name="log",amount=3}},
      owner_prerequisites={"automation-science-pack"},
      owner_science={{type="item",name="automation-science-pack",amount=1}},
    }},
    early={
      id="recipe-prod-research_material_py_log-1",
      science={"automation-science-pack"},
      prerequisites={"automation-science-pack", "wood-processing"},
      max_level=3, order="p[research_material_py_log]",
    },
    continuation={
      id="recipe-prod-research_material_py_log-4",
      science={"automation-science-pack", "utility-science-pack"},
      prerequisites={"automation-science-pack", "recipe-prod-research_material_py_log-1",
        "utility-science-pack", "wood-processing"},
      max_level=50000000, first_level=4, predecessor_count=800, previous_count=400,
      order="p[research_material_py_log__continuation]",
    },
  },
}
