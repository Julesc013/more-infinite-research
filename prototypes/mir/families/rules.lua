return {
  schema = 1,
  rules = {
    {
      id = "furnace-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_furnace",
      entity_types = {"furnace"},
      change = 0.02
    },
    {
      id = "inserter-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_inserters",
      entity_types = {"inserter"},
      change = 0.01
    },
    {
      id = "lab-manufacturing",
      capability = "recipe-productivity",
      mode = "proposal-only",
      entity_types = {"lab"},
      blocker = "no_stable_lab_manufacturing_stream"
    },
    {
      id = "loader-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_belts",
      entity_types = {"loader", "loader-1x1"},
      change = 0.01
    },
    {
      id = "logistics-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_belts",
      entity_types = {"splitter", "transport-belt", "underground-belt"},
      change = 0.01
    },
    {
      id = "mining-drill-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_mining_drill",
      entity_types = {"mining-drill"},
      change = 0.05
    },
    {
      id = "module-manufacturing",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_modules",
      item_prototype_types = {"module"},
      tier_changes = {0.10, 0.05, 0.02},
      high_tier_change = 0.01
    },
    {
      id = "power-storage-and-generation",
      capability = "recipe-productivity",
      mode = "attach-existing",
      target_stream = "research_electric_energy",
      entity_types = {"accumulator", "solar-panel"},
      change = 0.02
    }
  }
}

