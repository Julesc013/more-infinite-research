---
title: "GenerationPlan Schema"
status: current
applies_to: "post-3.1 dev"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# GenerationPlan Schema

`GenerationPlan` is the side-effect-free boundary between stream planning and prototype emission. The compiler creates every row, validates the complete set, and only then passes the finalized snapshot to mutation code.

Every schema-1 row contains:

| Field | Meaning |
| --- | --- |
| `schema` | Row schema version; currently `1`. |
| `manifest_id` | Stable generated-stream manifest identity. |
| `stream_key` | Stable stream declaration key. |
| `action` | `emit`, `adopt`, or `skip`. |
| `source` | Provenance class such as `fixed-stream`. |
| `reason` | Stable decision reason. |
| `spec` | Canonical stream descriptor snapshot. |
| `diagnostics` | Decision/report payload materialized after validation. |

An `emit` row also contains the stable technology name and all fields required by `StreamSpec`: effects, science ingredients, prerequisites, cost formula, research time, and maximum level. An `adopt` row contains the existing owner and exact effects to attach. A `skip` row contains no mutation intent.

Whole-plan validation rejects duplicate stream keys, emitted manifest IDs, technology names, and owner/recipe adoption identities. A finalized plan is immutable to consumers because `snapshot()` returns a deep copy.

