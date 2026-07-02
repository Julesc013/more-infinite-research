return {
  research_copper = { items={"copper-plate"}, icon_item="copper-plate" },
  research_iron   = { items={"iron-plate"}, icon_item="iron-plate" },
  research_gears = { items={"iron-gear-wheel"}, icon_item="iron-gear-wheel", exclude_ingredient_patterns={"scrap"} },
  research_iron_sticks = { items={"iron-stick"}, icon_item="iron-stick", exclude_ingredient_patterns={"scrap"} },
  research_copper_cable = { items={"copper-cable"}, icon_item="copper-cable", exclude_ingredient_patterns={"scrap"} },

  research_electronic_circuit = { items={"electronic-circuit"}, icon_tech="electronics", exclude_ingredient_patterns={"scrap"} },
  research_advanced_circuit = { items={"advanced-circuit"}, icon_tech="advanced-circuit", exclude_ingredient_patterns={"scrap"} },
  research_processing_unit = {
    items={"processing-unit"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/processing-unit-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="processing-unit"},
      {technology="advanced-electronics-2"}
    }
  },

  research_plastic = {
    items={"plastic-bar"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/plastics-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="plastics"}
    }
  },
  research_sulfur  = { items={"sulfur"}, icon_tech="sulfur-processing", exclude_ingredient_patterns={"asteroid"} },
  research_batteries = { items={"battery"}, icon_tech="battery", exclude_ingredient_patterns={"scrap"} },
  research_explosives = { items={"explosives"}, item_patterns={"^bio%-explosives$"}, icon_tech="explosives" },

  research_engine = { items={"engine-unit"}, icon_tech="engine" },
  research_electric_engine = { items={"electric-engine-unit"}, icon_tech="electric-engine" },
  research_flying_robot_frame = { items={"flying-robot-frame"}, icon_tech="robotics" },

  research_low_density_structure = {
    items={"low-density-structure"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/low-density-structure-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="low-density-structure"}
    }
  },
  research_rocket_fuel = {
    items={"rocket-fuel"},
    icon_candidates={
      {icon="__space-age__/graphics/technology/rocket-fuel-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="rocket-fuel"}
    }
  },

  research_tungsten = { items={"tungsten-plate","tungsten-carbide"}, icon_item="tungsten-plate", icon_tech="tungsten-processing" },
  research_lithium = { items={"lithium-plate"}, icon_tech="lithium-processing" },
  research_holmium = { items={"holmium-plate"}, icon_tech="holmium-processing" },
  research_supercapacitor = { items={"supercapacitor"}, icon_tech="supercapacitor" },
  research_superconductor = { items={"superconductor"}, icon_tech="superconductor" },
  research_quantum_processor = { items={"quantum-processor"}, icon_tech="quantum-processor" },
  research_carbon_fiber = { items={"carbon-fiber"}, icon_tech="carbon-fiber" },

  research_bioflux = { items={"bioflux"}, icon_tech="bioflux" },
  research_breeding = { items = {"raw-fish","biter-egg","pentapod-egg"}, mode = "by_category_or_match", match = { name_patterns={"cultivation","culture","breeding"} }, icon_tech = "fish-breeding" },

  research_grenades = { icon_item="grenade", groups = {
    {change=0.10, items={"grenade"}},
    {change=0.05, items={"cluster-grenade"}}
  } },

  research_walls = { icon_tech="gate", icon_item="stone-wall", groups = {
    {change=0.10, items={"stone-wall"}},
    {change=0.05, items={"gate"}}
  } },

  research_stone_products = { icon_item = "stone", groups = {
    { change = 0.10, items = { "stone", "landfill" } },
    { change = 0.05, items = { "foundation" }, item_patterns = { "^artificial%-.+%-soil$" } }
  }, exclude_ingredient_patterns={"scrap"} },

  research_rails = { icon_item="rail", items = {"rail"} },

  research_concrete = { icon_tech = "concrete", groups = {
    { change = 0.10, items = { "stone-brick" } },
    { change = 0.05, items = { "concrete", "hazard-concrete" } },
    { change = 0.02, items = { "refined-concrete", "refined-hazard-concrete" } }
  }, exclude_ingredient_patterns={"scrap"} },

  research_furnace = { icon_tech = "advanced-material-processing-2", groups = {
    { change = 0.20, items = { "stone-furnace" } },
    { change = 0.10, items = { "steel-furnace" } },
    { change = 0.05, items = { "electric-furnace" } },
    { change = 0.02, items = { "foundry" }, item_patterns = { "^foundry$" } }
  } },

  research_mining_drill = { icon_tech = "electric-mining", icon_item = "electric-mining-drill", groups = {
    { change = 0.20, items = { "burner-mining-drill" } },
    { change = 0.10, items = { "electric-mining-drill" } },
    { change = 0.05, items = { "big-mining-drill" }, item_patterns = {
      "^big%-mining%-drill$",
      "^omega%-drill$",
      "^omega%-tau$",
      "^.+%-mining%-drill$",
      "^.+%-drill$"
    } }
  } },

  research_electric_energy = { icon_tech="electric-energy-accumulators", groups = {
    { change=0.10, items={"solar-panel","accumulator"} },
    { change=0.05, items={"advanced-solar","advanced-accumulator"} },
    { change=0.02, items={"elite-solar","elite-accumulator"} },
    { change=0.01, items={"ultimate-solar","ultimate-accumulator"} }
  } },

  research_bullets = { icon_tech="military", groups = {
    { change=0.10, items={"firearm-magazine","shotgun-shell"} },
    { change=0.05, items={"piercing-rounds-magazine","piercing-shotgun-shell"} },
    { change=0.02, items={"uranium-rounds-magazine","uranium-shotgun-shell"} },
    { change=0.01, item_patterns={
      "^plutonium%-.+magazine$","^plutonium%-.+shotgun%-shell$",
      "^tungsten%-.+magazine$","^tungsten%-.+shotgun%-shell$"
    } }
  }},

  research_heavy_ammo = { icon_item="cannon-shell", groups = {
    { change=0.10, items={"cannon-shell"} },
    { change=0.05, items={"explosive-cannon-shell"} },
    { change=0.02, items={"uranium-cannon-shell","explosive-uranium-cannon-shell"} },
    { change=0.01, items={"artillery-shell","railgun-ammo"}, item_patterns={
      "^.+%-cannon%-shell$","^.+%-artillery%-shell$","^.+%-railgun%-ammo$"
    } }
  }},

  research_rockets = { icon_tech="rocketry", groups = {
    { change=0.10, items={"rocket"} },
    { change=0.05, items={"explosive-rocket"} },
    { change=0.02, items={"atomic-bomb"} },
    { change=0.01, items={"plutonium-bomb"}, item_patterns={"^plutonium%-bomb$","^plutonium%-.+bomb$"} }
  }},

  research_armor_components = { icon_tech="power-armor", groups = {
    { change=0.05, item_patterns={
      "^.+%-armor%-plating$","^.+%-armour%-plating$",
      "^armor%-plating.*$","^armour%-plating.*$"
    } },
    { change=0.02, item_patterns={
      "^.+%-armor%-plate$","^.+%-armour%-plate$",
      "^armor%-plate.*$","^armour%-plate.*$"
    } }
  }},

  research_modules = { icon_tech="modules", groups = {
    { change=0.10, items={"productivity-module","speed-module","efficiency-module","quality-module"} },
    { change=0.05, items={"productivity-module-2","speed-module-2","efficiency-module-2","quality-module-2"} },
    { change=0.02, items={"productivity-module-3","speed-module-3","efficiency-module-3","quality-module-3"} }
  }},

  research_belts = { icon_tech="logistics", groups = {
    { change=0.10, items={"transport-belt","underground-belt","splitter"} },
    { change=0.05, items={"fast-transport-belt","fast-underground-belt","fast-splitter"} },
    { change=0.02, items={"express-transport-belt","express-underground-belt","express-splitter"} },
    { change=0.01, items={"turbo-transport-belt","turbo-underground-belt","turbo-splitter"}, item_patterns={"^turbo%-transport%-belt$","^turbo%-underground%-belt$","^turbo%-splitter$"} },
    { change=0.005, items={"hyper-transport-belt","hyper-underground-belt","hyper-splitter"}, item_patterns={"^hyper%-transport%-belt$","^hyper%-underground%-belt$","^hyper%-splitter$"} }
  }},

  research_inserters = { icon_tech="fast-inserter", groups = {
    { change=0.10, items={"inserter","burner-inserter"} },
    { change=0.05, items={"fast-inserter","long-handed-inserter"} },
    { change=0.02, items={"bulk-inserter"}, item_patterns={"bulk%-inserter"} },
    { change=0.01, items={"stack-inserter"}, item_patterns={"stack%-inserter"} }
  }},

  research_science_pack_productivity = {
    icon_candidates={
      {technology="research-productivity", required_mod="space-age"},
      {icon="__space-age__/graphics/technology/research-productivity.png", icon_size=256, inactive_mod_asset="space-age"},
      {technology="space-science-pack"},
      {item="automation-science-pack"}
    },
    dynamic_items_from_lab_inputs = true,
    groups = {
    { change=0.10, items={
      "automation-science-pack","logistic-science-pack","chemical-science-pack","production-science-pack",
      "military-science-pack","utility-science-pack","space-science-pack",
      "agricultural-science-pack","metallurgic-science-pack","electromagnetic-science-pack","cryogenic-science-pack","promethium-science-pack"
    }}
  }}
}
