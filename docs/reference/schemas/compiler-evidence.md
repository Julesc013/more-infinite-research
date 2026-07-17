---
title: "CompilerEvidence Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-17
supersedes: []
superseded_by: []
---

# CompilerEvidence Schema

`CompilerEvidence` schema 1 is published only after MIR postconditions and output parity succeed. The `more-infinite-research-compiler-evidence` mod-data prototype persists the semantic `CompilationPlan` fingerprint separately from operational telemetry.

The artifact contains `semantic_fingerprint`, `telemetry_fingerprint`, deterministic `input_sanitation_ledger` and `output_sanitation_ledger` records, a fingerprint for each ledger, and `evidence_fingerprint` for the complete envelope. Each affected technology ledger row records the original technology name and effect count, owner kind, owning mod or explicit unknown status, removed effects with original indexes and targets, and the exact retained original effect order.

The input ledger is created after exact compatibility repairs and before indexes or planning. The output ledger is created after every emission and mutation pass but before reports, output parity, and publication. Telemetry can change the evidence-envelope fingerprint but cannot change the semantic compiler identity.
