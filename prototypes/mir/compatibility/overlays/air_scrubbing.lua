return {
  schema = 1,
  id = "air-scrubbing",
  applies_when = {
    mods = { "atan-air-scrubbing" }
  },

  claim = {
    level = "full-family-support",
    target = "atan-air-scrubbing",
    text = "Clean-filter crafting productivity only; scrubbing and cleaning recipes remain diagnostic-only.",
    evidence = {
      fixtures = {
        "fixtures/air-scrubbing",
        "fixtures/assert-air-scrubbing-clean-filter"
      }
    }
  },

  capabilities = {
    ["recipe-productivity"] = {
      mode = "exact",
      min_confidence = 1.0,
      family = "clean_filter",
      stream = {
        id = "mir-prod-air-scrubbing-clean-filter",
        key = "research_air_scrubbing_clean_filter",
        technology = "recipe-prod-research_air_scrubbing_clean_filter-1"
      },
      exact_recipes = {
        "atan-pollution-filter",
        "atan-spore-filter"
      },
      deny_families = {
        "scrubbing_environmental",
        "cleaning_recovery"
      },
      deny_risk_flags = {
        "scrubbing_environmental",
        "cleaning_recovery",
        "unknown_related_recipe"
      },
      science = {
        mode = "derive_from_unlocks",
        require_lab_compatible = true
      },
      diagnostics = {
        policy_summary_reason = "air_scrubbing_policy_summary",
        missing_target_reason = "missing_target_recipe",
        unknown_reason = "related_recipe_not_classified"
      }
    }
  }
}
