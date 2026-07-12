local COMMON_REQUIREMENTS = {
  visible_recipe = true,
  parameter = false,
  productivity_supported = true,
  output_placeable = true,
  researchable = true,
  lab_compatible = true
}

local COMMON_DENY_RISKS = {
  "recycling_loop",
  "catalyst_or_self_return",
  "non_deterministic_output",
  "voiding_or_destruction",
  "matter_or_transmutation",
  "hidden_internal"
}

local function structural_rule(row)
  row.schema = 2
  row.capability = "recipe-productivity"
  row.required_evidence = {
    "recipe-fact-v2",
    "place-result-index",
    "effect-owner-index"
  }
  row.require = COMMON_REQUIREMENTS
  row.deny_risks = COMMON_DENY_RISKS
  row.ownership = {strategy = "prefer-existing-exact-owner"}
  row.science = {strategy = "inherit-target-stream"}
  row.prerequisites = {strategy = "inherit-target-stream"}
  row.targets = {requires_features = {"recipe_productivity"}}
  row.default_action = "attach-existing"
  row.support_claim = {level = "structural-attachment", public = false}
  return row
end

local function placeable(id, stream, entity_types, change)
  return structural_rule({
    id = id,
    family = id,
    selector = {
      output_item = {place_result_entity_types = entity_types}
    },
    grouping = {strategy = "attach-existing", stream = stream},
    tier = {strategy = "structural-single-tier"},
    effects = {strategy = "fixed", default = change}
  })
end

return {
  schema = 2,
  rules = {
    placeable("assembling-machine-manufacturing", "research_auto_assembling_machine", {"assembling-machine"}, 0.02),
    placeable("furnace-manufacturing", "research_furnace", {"furnace"}, 0.02),
    placeable("inserter-manufacturing", "research_inserters", {"inserter"}, 0.01),
    placeable("lab-manufacturing", "research_auto_lab", {"lab"}, 0.02),
    placeable("loader-manufacturing", "research_belts", {"loader", "loader-1x1"}, 0.01),
    placeable("logistics-manufacturing", "research_belts", {"splitter", "transport-belt", "underground-belt"}, 0.01),
    placeable("mining-drill-manufacturing", "research_mining_drill", {"mining-drill"}, 0.05),
    structural_rule({
      id = "module-manufacturing",
      family = "module-manufacturing",
      selector = {
        output_item = {prototype_types = {"module"}}
      },
      grouping = {strategy = "attach-existing", stream = "research_modules"},
      tier = {strategy = "item-prototype-tier"},
      effects = {
        strategy = "tier-table",
        tiers = {0.10, 0.05, 0.02},
        high_tier = 0.01,
        default = 0.01
      }
    }),
    placeable("power-storage-and-generation", "research_electric_energy", {"accumulator", "solar-panel"}, 0.02)
  }
}
