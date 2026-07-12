---
title: "GenerationPlan Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# GenerationPlan Schema

`GenerationPlan` is the side-effect-free boundary between stream planning and prototype emission. The compiler creates every row, validates the complete set, and only then passes the finalized snapshot to mutation code.

The exported stream plan artifact is schema 3. It contains a deterministic plan fingerprint, fingerprints for facts, rules, active compatibility packs, and the target profile, the complete row set, and a validation summary with action and reason counts. A compilation-plan envelope is assembled before emission and also carries the validated base-extension operations, so base continuations do not rediscover their decisions during apply.

Every schema-3 row contains:

| Field | Meaning |
| --- | --- |
| `schema` | Row schema version; currently `3`. |
| `manifest_id` | Stable generated-stream manifest identity. |
| `stream_key` | Stable stream declaration key. |
| `action` | `emit`, `adopt`, or `skip`. |
| `source` | Provenance class such as `fixed-stream`. |
| `reason` | Stable decision reason. |
| `spec` | Canonical stream descriptor snapshot. |
| `diagnostics` | Decision/report payload materialized after validation. |
| `gates` | Evidence records for target, effect, owner, science, lab, prerequisites, loops, progression, migration, and output identity. |

An `emit` row also contains the stable technology name and all fields required by `StreamSpec`: effects, science ingredients, prerequisites, cost formula, research time, and maximum level. An `adopt` row contains the existing owner and exact effects to attach. A `skip` row contains no mutation intent.

Each gate records `passed`, a `passed`, `failed`, or `not-applicable` status, stable evidence IDs, and an optional reason. Materializing rows must pass every gate. Skip rows record the failed or inapplicable proof directly instead of encoding gate state in a reason string.

Whole-plan validation rejects duplicate stream keys, emitted manifest IDs, technology names, owner/recipe adoption identities, duplicate semantic effect identities across emission and adoption, and any materializing row whose proof gate fails. After all mutations, the output validator proves that every planned technology/effect exists and that every planned infinite recipe-productivity effect has exactly the expected final owner. A finalized plan is immutable to consumers because `snapshot()` and `artifact()` return deep copies.
