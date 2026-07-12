---
title: "Decision Records And Stream Specs"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---
# Decision Records And Stream Specs

Updated: 2026-07-07

Decision records are the audit trail for the MIR compatibility compiler. They explain why a candidate generated, skipped, rejected, or remained diagnostic.

Current generated-technology rows are normalized by `prototypes/mir/domain/decisions/decision_record.lua` before `prototypes/mir/planner/compiler.lua` passes them to diagnostics. This keeps the legacy planner output stable while moving row construction behind the MIR 3 domain boundary.

## DecisionRecord V2

Minimum shape:

```lua
DecisionRecord = {
  schema = 2,
  subject_type = "recipe",
  subject = "atan-pollution-filter",
  capability = "recipe-productivity.clean-filter",
  family = "clean_filter",
  subfamily = "air-scrubbing",
  decision = "generate_stream",
  confidence = {
    identity = "exact",
    family = "exact",
    tier = "exact",
    science = "exact",
    lab = "exact",
    owner = "exact",
    loop_safety = "exact",
    total = 1.0,
    scores = {},
  },
  emitted = true,
  source = "compat_policy:air-scrubbing",
  policy = "air-scrubbing.clean-filter",
  evidence = {},
  blockers = {},
  risks = {},
  stable_stream_id = "mir-prod-air-scrubbing-clean-filter",
}
```

For a rejected loop:

```lua
DecisionRecord = {
  schema = 2,
  subject_type = "recipe",
  subject = "atan-clean-pollution-filter",
  capability = "recipe-productivity.clean-filter",
  family = "cleaning_recovery",
  decision = "diagnose_only",
  confidence = {
    identity = "structural",
    family = "structural",
    tier = "heuristic",
    science = "inferred",
    lab = "inferred",
    owner = "inferred",
    loop_safety = "heuristic",
    total = 0.25,
  },
  emitted = false,
  reason = "recovery loop; productivity could duplicate returned filters or recovery outputs",
  risks = { "cleaning_recovery" },
  blockers = { "loop_risk" },
}
```

## Decision Values

Confidence evidence classes are `exact`, `structural`, `inferred`, and `heuristic`. The numeric `total` ranks review priority only. It never overrides target, effect, owner, science, lab, prerequisite, or loop-safety gates.

Use stable values:

| Decision | Meaning |
| --- | --- |
| `generate_stream` | MIR emitted or attached to an emitted stream. |
| `skip_existing_owner` | Another owner is preferred or exact owner conflict blocks MIR. |
| `diagnose_only` | Candidate is recognized but not emitted. |
| `reject_loop_risk` | Candidate is unsafe by loop-risk policy. |
| `reject_hidden` | Candidate is hidden/internal without explicit policy. |
| `reject_cap_zero` | Recipe cannot benefit from productivity. |
| `reject_lab_incompatible` | No lab can research the generated technology. |
| `observe_unknown` | Candidate is related but not confidently classified. |
| `missing_target` | Exact policy target is absent in the active mod set. |

## StreamSpec V1

Only `StreamSpec` records may cross into the emission layer:

```lua
StreamSpec = {
  schema = 1,
  id = "mir-prod-air-scrubbing-clean-filter",
  capability = "recipe-productivity.clean-filter",
  family = "clean_filter",
  owner = "MIR",
  source = "compat_policy:air-scrubbing",
  targets = {
    {
      recipe = "atan-pollution-filter",
      effect = "change-recipe-productivity",
      change = 0.05,
    },
  },
  science = {
    mode = "derive_from_unlocks",
    require_lab_compatible = true,
  },
  cap_policy = "warn_only",
  risk_policy = "deny_loop_risk",
}
```

## Determinism

Decision output must be stable:

- sort subjects by type and name;
- sort targets by recipe ID;
- sort evidence keys;
- sort blockers and risks;
- avoid run-specific hashes in exact curated stream IDs;
- keep JSON key ordering stable where scripts can control it.

Stable rows make fixture diffs meaningful and save compatibility review possible.
