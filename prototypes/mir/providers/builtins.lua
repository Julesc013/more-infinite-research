local diagnostics = require("prototypes.mir.domain.diagnostics.codes")

local COMMON_REQUIREMENTS = {
  visible_recipe = true,
  parameter = false,
  productivity_supported = true,
  output_placeable = true,
  researchable = true,
  lab_compatible = true
}

local COMMON_DENY_RISKS = {
  "recycling_loop", "catalyst_or_self_return", "non_deterministic_output",
  "voiding_or_destruction", "matter_or_transmutation", "hidden_internal"
}

local COMMON_CARDINALITY = {
  maximum_candidates = 256,
  maximum_attachments = 128,
  maximum_review_required = 64,
  maximum_new_attachments = 128,
  maximum_growth_percent = 400,
  maximum_progression_span = 1,
  maximum_semantic_clusters = 256,
  maximum_unreviewed = 128
}

local function structural_rule(provider_id, row)
  row.schema = 2
  row.provider_id = provider_id
  row.capability = "recipe-productivity"
  row.required_evidence = {"recipe-fact-v2", "place-result-index", "effect-owner-index"}
  row.require = COMMON_REQUIREMENTS
  row.deny_risks = COMMON_DENY_RISKS
  row.ownership = {strategy = "prefer-existing-exact-owner"}
  row.science = {strategy = "inherit-target-stream"}
  row.prerequisites = {strategy = "inherit-target-stream"}
  row.targets = {requires_features = {"recipe_productivity"}}
  row.default_action = "attach-existing"
  row.cardinality = COMMON_CARDINALITY
  row.support_claim = {level = "structural-attachment", public = false}
  local discovery_selector
  if row.selector.output_item.place_result_entity_types then
    discovery_selector = {
      operator = "output.place-result",
      entity_types = row.selector.output_item.place_result_entity_types
    }
  else
    discovery_selector = {
      operator = "output.prototype-type",
      prototype_type = row.selector.output_item.prototype_types[1]
    }
  end
  row.operators = {
    schema = 1,
    selectors = {
      {operator = "recipe.visible"},
      {operator = "recipe.parameter-absent"},
      {operator = "recipe.productivity-eligible"},
      {operator = "output.deterministic-single-placeable"},
      discovery_selector,
      {operator = "risk.none", risks = COMMON_DENY_RISKS}
    },
    normalizers = {{operator = "candidate.recipe-item-entity"}},
    partitioner = {operator = "partition.single"},
    tier_resolver = {operator = row.tier.strategy == "item-prototype-tier"
      and "tier.item-prototype" or "tier.structural-single"},
    effect_model = row.effects.strategy == "tier-table" and {
      operator = "effect.tier-table", tiers = row.effects.tiers, high_tier = row.effects.high_tier,
      default = row.effects.default
    } or {operator = "effect.fixed", change = row.effects.default},
    science_model = {operator = "science.inherit-target-stream"},
    prerequisite_model = {operator = "prerequisite.inherit-target-stream"},
    cost_model = {operator = "cost.inherit-target-stream"},
    presentation_model = {operator = "presentation.inherit-target-stream"},
    ownership_policy = {operator = "ownership.prefer-existing-exact-owner"},
    grouping = {
      operator = row.grouping.strategy == "proposal-only" and "group.proposal-only" or "group.attach-existing",
      stream = row.grouping.stream
    }
  }
  return row
end

local function placeable_rule(provider_id, family, stream, entity_types, change)
  return structural_rule(provider_id, {
    id = family,
    family = family,
    selector = {output_item = {place_result_entity_types = entity_types}},
    grouping = {strategy = "attach-existing", stream = stream},
    tier = {strategy = "structural-single-tier"},
    effects = {strategy = "fixed", default = change}
  })
end

local function provider(id, family, rule)
  return {
    schema_version = 1,
    id = id,
    source_kinds = {"recipe", "item"},
    discovery = {kind = "final-prototype-facts", indexes = {"recipe-fact-v2", "place-result-index", "effect-owner-index"}},
    positive_capabilities = {"recipe-productivity", "researchable", "lab-compatible"},
    family = family,
    normalization = {kind = "canonical-recipe-item-entity", version = 1},
    semantic_signature = {kind = "prototype-structure", version = 1},
    default_policy = {
      action = "attach-existing",
      fail_closed = true,
      cardinality = COMMON_CARDINALITY
    },
    setting_descriptors = {
      "mir-automatic-productivity-action", "mir-automatic-create-research", "mir-automatic-require-reviewed-data"
    },
    localization_descriptors = {"automatic-productivity-support", "automatic-provider-diagnostics"},
    validation_hooks = {
      "target-supported", "productivity-supported", "owner-conflict-free", "loop-safe",
      "science-compatible", "lab-compatible", "prerequisites-acyclic", "identity-safe"
    },
    emission_adapter = {kind = "generation-plan-family-rule", mutates_prototypes = false},
    runtime_handler = {required = false},
    migration = {identity = "stable-provider-and-family-id", prior_schema = 0},
    diagnostic_codes = {
      diagnostics.get("provider_candidate_discovered"), diagnostics.get("provider_candidate_rejected"),
      diagnostics.get("provider_candidate_attached"), diagnostics.get("provider_candidate_planned")
    },
    fixtures = {"compiler-contracts", "semantic-family-attach", "semantic-family-generate"},
    family_rule = rule
  }
end

local definitions = {
  {"mir.assembling-machine-manufacturing", "assembling-machine-manufacturing", "research_auto_assembling_machine", {"assembling-machine"}, 0.02},
  {"mir.furnace-manufacturing", "furnace-manufacturing", "research_furnace", {"furnace"}, 0.02},
  {"mir.inserter-manufacturing", "inserter-manufacturing", "research_inserters", {"inserter"}, 0.01},
  {"mir.lab-manufacturing", "lab-manufacturing", "research_auto_lab", {"lab"}, 0.02},
  {"mir.loader-manufacturing", "loader-manufacturing", "research_belts", {"loader", "loader-1x1"}, 0.01},
  {"mir.logistics-manufacturing", "logistics-manufacturing", "research_belts", {"splitter", "transport-belt", "underground-belt"}, 0.01},
  {"mir.mining-drill-manufacturing", "mining-drill-manufacturing", "research_mining_drill", {"mining-drill"}, 0.05},
  {"mir.power-storage-and-generation", "power-storage-and-generation", "research_electric_energy", {"accumulator", "solar-panel"}, 0.02}
}

local providers = {}
for _, row in ipairs(definitions) do
  local id, family = row[1], row[2]
  table.insert(providers, provider(id, family, placeable_rule(id, family, row[3], row[4], row[5])))
end

local module_id = "mir.module-manufacturing"
table.insert(providers, provider(module_id, "module-manufacturing", structural_rule(module_id, {
  id = "module-manufacturing",
  family = "module-manufacturing",
  selector = {output_item = {prototype_types = {"module"}}},
  grouping = {strategy = "attach-existing", stream = "research_modules"},
  tier = {strategy = "item-prototype-tier"},
  effects = {strategy = "tier-table", tiers = {0.10, 0.05, 0.02}, high_tier = 0.01, default = 0.01}
})))

return {schema = 1, providers = providers}
