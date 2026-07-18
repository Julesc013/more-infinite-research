---
title: "GenerationPlan Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-17
supersedes: []
superseded_by: []
---

# GenerationPlan Schema

`GenerationPlan` is the side-effect-free boundary between stream planning and prototype emission. The compiler creates every row, validates the complete set, and only then passes the finalized snapshot to mutation code.

The exported stream plan artifact is schema 3. It contains a deterministic plan fingerprint, fingerprints for facts, rules, active compatibility packs, and the target profile, the complete row set, and a validation summary with action and reason counts.

`CompilationPlan` schema 2 globally finalizes materializing stream, adoption, and base-extension operations before the first emission. It adds a base-operation source fingerprint, stable operation ordering, and validation summary, and rejects cross-part technology names, manifests, direct-effect identities, missing prerequisite targets, and unsupported effects. Accepted base extensions carry a continuation-manifest identity and schema-2 `TechnologyDesign`; the plan rebuilds their projection after sanitation and cross-operation policy. `compilation_fingerprint` identifies selected accepted and rejected operations plus policies, `qualification_fingerprint` additionally binds exact gates and evidence, and `run_fingerprint` binds qualification to operational telemetry. `semantic_fingerprint` remains a compatibility alias for qualification, while `fingerprint` aliases compilation.

After postconditions pass, target-neutral `CompilerEvidence` schema 2 binds compilation, qualification, run, telemetry, deterministic pre-index and post-emission sanitation ledgers, individual ledger fingerprints, and an evidence-envelope fingerprint. Factorio 2.1 publishes the canonical object through a `mod-data` adapter; reduced targets may use the validation-log adapter. Unknown external prototype ownership is recorded explicitly rather than guessed.

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
| `technology_design` | Required schema-2 common design IR for every `emit` and `adopt` row, with typed subjects, per-field provenance, executable locks, authority-derived identity state, independent fingerprints, and multi-axis maturity. |

An `emit` row also contains the stable technology name and all fields required by `StreamSpec`: effects, science ingredients, prerequisites, cost formula, research time, and maximum level. An `adopt` row contains the existing owner, exact effects to attach, an immutable input fingerprint, the complete expected owner snapshot, and a `patch-existing` TechnologyDesign whose prototype fingerprint equals the transaction output fingerprint. A `skip` row contains no mutation intent.

Each gate records `passed`, a `passed`, `failed`, or `not-applicable` status, stable evidence IDs, and an optional reason. Materializing rows must pass every gate. Skip rows record the failed or inapplicable proof directly instead of encoding gate state in a reason string.

Whole-plan validation rejects duplicate stream keys, emitted manifest IDs, technology names, owner/recipe adoption identities, duplicate semantic effect identities across emission and adoption, any materializing row whose proof gate fails, and any legacy projection that disagrees with `TechnologyDesign`. The adoption transaction verifies the current owner against the immutable input fingerprint before mutation and the TechnologyDesign projection against the declared expected snapshot and output fingerprint before applying it. After all mutations, the compilation output validator compares full normalized effect values with a declared tolerance plus prerequisites, science ingredients, count formula, research time, maximum level, localized name, localized description, single or layered icons, order, level, enabled/hidden/upgrade state when declared, and generated-registry records. Stream adoption is checked against its complete patch-existing projection; emitted stream and base-extension technologies require exact planned shapes. Snapshots are deep copies.
