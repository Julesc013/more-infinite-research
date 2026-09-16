return {
  schema = 1,
  id = "atan-ash",
  applies_when = {
    mods = { "atan-ash" }
  },

  claim = {
    level = "full-family-support",
    target = "atan-ash",
    text = "Ash separation productivity only; landfill, brick, nutrient, foundation, tile, and recovery-style ash sinks remain outside this stream.",
    evidence = {
      fixtures = {
        "fixtures/atan-ash",
        "fixtures/assert-atan-ash-separation"
      }
    }
  },

  capabilities = {
    ["recipe-productivity"] = {
      mode = "exact",
      min_confidence = 1.0,
      family = "ash_separation",
      stream = {
        id = "mir-prod-atan-ash-separation",
        key = "research_ash_separation",
        technology = "recipe-prod-research_ash_separation-1"
      },
      exact_recipes = {
        "atan-ash-seperation"
      },
      deny_families = {
        "ash_sink",
        "tile_surface",
        "resource_recovery"
      },
      deny_risk_flags = {
        "ash_sink",
        "tile_surface",
        "resource_recovery"
      },
      science = {
        mode = "derive_from_unlocks",
        require_lab_compatible = true
      },
      diagnostics = {
        policy_summary_reason = "atan_ash_policy_summary",
        missing_target_reason = "missing_target_recipe",
        denied_reason = "ash_sink_outside_stream"
      }
    }
  }
}
