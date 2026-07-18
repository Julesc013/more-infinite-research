---
title: "CompilerEvidence Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# CompilerEvidence Schema

`CompilerEvidence` schema 2 is a target-neutral canonical data object built only after MIR postconditions and output parity succeed. `prototypes/mir/domain/evidence/compiler_evidence.lua` owns the object; publication transport is separate.

The artifact contains `compilation_fingerprint`, `qualification_fingerprint`, the compatibility `semantic_fingerprint` alias, `telemetry_fingerprint`, `run_fingerprint`, deterministic `input_sanitation_ledger` and `output_sanitation_ledger` records, a fingerprint for each ledger, and `evidence_fingerprint` for the complete envelope.

Each affected technology ledger row records the original technology name and effect count, owner kind, owning mod or explicit unknown status, `original_effects_fingerprint`, removed effects with original indexes and full-effect fingerprints, exact retained original order, retained semantic identities, `retained_effects_fingerprint`, and `sanitized_effects_fingerprint`. Both passes also bind the complete inventory of sanitation-covered target prototype families. Output publication fails if MIR created or removed one of those targets after input sanitation.

Factorio 2.1 publishes the object through `more-infinite-research-compiler-evidence` using the `mod-data` adapter. A target without `mod-data` uses a validation-log envelope containing the same canonical fingerprints. Developer JSON and harness extraction can serialize the same object without redefining its semantics.
