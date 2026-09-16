-- Generated from .mir/technology-quality-profiles.json. Do not edit by hand.
return {
  authority = "mir-technology-quality-profiles-v2",
  profiles = {
    {
      candidate_class = "existing-stream-attachment",
      maximum_cross_version_additions = 128,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 512,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 128,
      maximum_provider_canonical_bytes = 1048576,
      maximum_provider_phase_seconds = 0.5,
      maximum_provider_witnesses = 256,
      maximum_science_tier_span = 6,
      maximum_semantic_clusters = 128,
      minimum_accepting_labs = 1,
      minimum_members = 1,
      minimum_useful_levels_before_cap = 5,
      profile_id = "existing-stream-attachment-v1",
      required_observational_evidence = {
        "exact-target-load",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "exact-stream-identity",
        "exact-attachment-delta",
        "zero-ownership-ambiguity"
      }
    },
    {
      candidate_class = "native-owner-patch",
      maximum_cross_version_additions = 0,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 64,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 64,
      maximum_provider_canonical_bytes = 524288,
      maximum_provider_phase_seconds = 0.25,
      maximum_provider_witnesses = 128,
      maximum_science_tier_span = 6,
      maximum_semantic_clusters = 16,
      minimum_accepting_labs = 1,
      minimum_members = 1,
      minimum_useful_levels_before_cap = 5,
      profile_id = "native-owner-patch-v1",
      required_observational_evidence = {
        "exact-target-load",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "exact-pre-ownership-fingerprint",
        "exact-post-ownership-fingerprint",
        "bounded-native-field-delta"
      }
    },
    {
      candidate_class = "base-continuation",
      maximum_cross_version_additions = 1,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 1,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 16,
      maximum_provider_canonical_bytes = 131072,
      maximum_provider_phase_seconds = 0.1,
      maximum_provider_witnesses = 32,
      maximum_science_tier_span = 4,
      maximum_semantic_clusters = 1,
      minimum_accepting_labs = 1,
      minimum_members = 1,
      minimum_useful_levels_before_cap = 10,
      profile_id = "base-continuation-v1",
      required_observational_evidence = {
        "base-load",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "exact-base-owner",
        "progression-proof",
        "effect-target-proof"
      }
    },
    {
      candidate_class = "new-machine-manufacturing",
      maximum_cross_version_additions = 16,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 64,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 32,
      maximum_provider_canonical_bytes = 524288,
      maximum_provider_phase_seconds = 0.25,
      maximum_provider_witnesses = 128,
      maximum_science_tier_span = 3,
      maximum_semantic_clusters = 16,
      minimum_accepting_labs = 1,
      minimum_members = 2,
      minimum_useful_levels_before_cap = 10,
      profile_id = "new-machine-manufacturing-v1",
      required_observational_evidence = {
        "exact-target-load",
        "representative-balance-review",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "family-coherence",
        "exact-machine-membership",
        "progression-proof"
      }
    },
    {
      candidate_class = "new-lab-manufacturing",
      maximum_cross_version_additions = 8,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 16,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 16,
      maximum_provider_canonical_bytes = 262144,
      maximum_provider_phase_seconds = 0.2,
      maximum_provider_witnesses = 64,
      maximum_science_tier_span = 2,
      maximum_semantic_clusters = 8,
      minimum_accepting_labs = 2,
      minimum_members = 2,
      minimum_useful_levels_before_cap = 10,
      profile_id = "new-lab-manufacturing-v1",
      required_observational_evidence = {
        "base-and-space-age-load",
        "technology-tree-review",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "family-coherence",
        "lab-acceptance-matrix",
        "progression-proof"
      }
    },
    {
      candidate_class = "exact-overhaul-material",
      maximum_cross_version_additions = 32,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 128,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 64,
      maximum_provider_canonical_bytes = 1048576,
      maximum_provider_phase_seconds = 0.4,
      maximum_provider_witnesses = 256,
      maximum_science_tier_span = 4,
      maximum_semantic_clusters = 32,
      minimum_accepting_labs = 1,
      minimum_members = 1,
      minimum_useful_levels_before_cap = 10,
      profile_id = "exact-overhaul-material-v1",
      required_observational_evidence = {
        "named-ecosystem-load",
        "representative-balance-review",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "exact-overhaul-profile",
        "exact-material-membership",
        "progression-proof"
      }
    },
    {
      candidate_class = "process-family-experimental",
      maximum_cross_version_additions = 16,
      maximum_cross_version_removals = 0,
      maximum_false_negatives = 0,
      maximum_false_positives = 0,
      maximum_members = 64,
      maximum_owner_conflicts = 0,
      maximum_progression_span = 32,
      maximum_provider_canonical_bytes = 524288,
      maximum_provider_phase_seconds = 0.25,
      maximum_provider_witnesses = 128,
      maximum_science_tier_span = 4,
      maximum_semantic_clusters = 16,
      minimum_accepting_labs = 1,
      minimum_members = 2,
      minimum_useful_levels_before_cap = 10,
      profile_id = "process-family-experimental-v1",
      required_observational_evidence = {
        "named-ecosystem-load",
        "experimental-design-review",
        "upgrade-and-removal"
      },
      required_semantic_evidence = {
        "cycle-analysis",
        "catalyst-accounting",
        "byproduct-accounting",
        "net-flow-proof"
      }
    }
  },
  schema = 2
}
