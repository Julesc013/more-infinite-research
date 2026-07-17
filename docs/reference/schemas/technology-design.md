---
title: "TechnologyDesign Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-17
supersedes: []
superseded_by: []
---

# TechnologyDesign Schema

`TechnologyDesign` schema 1 is the normalized design boundary shared by fixed and automatic stream technologies. It separates an evolving `candidate_id` from the released `technology_id`, records semantic family identity and members, and wraps every design dimension in an independent provenance record.

The required design dimensions are `identity`, `effects`, `progression`, `cost`, `presentation`, `ownership`, and `runtime_contracts`. Each dimension contains `value`, `source`, `evidence_class`, `locked`, and `lock_policy`. `provenance.fields` repeats that envelope at leaf-field paths such as `identity.technology_id`, `progression.science`, `cost.max_level`, and `presentation.icons`. A field can therefore remain graph-, setting-, target-, or fallback-adaptive even when another field on the same technology is reviewed and locked.

The maturity record keeps safety, discovery evidence, design maturity, validation evidence, applicability scope, identity stability, runtime action, and public claim independent. Passing one gate does not promote any unrelated maturity axis.

Schema-1 records carry a deterministic `semantic_fingerprint` over candidate identity, released identity, semantic identity, members, all design fields, gates, provenance, maturity, and context. The fingerprint excludes run timing and telemetry.

For the first 3.2 vertical slice, both fixed and automatic `emit` rows are normalized after cross-stream ownership arbitration. `CompilationPlan` derives its expected prototype shape from that record, and the stream emitter consumes that same record. Released technology names, effects, science, prerequisites, cost, presentation, migration policy, and registry identity remain unchanged. Native-owner adoption and base-extension migration to this IR remain explicitly pending.
