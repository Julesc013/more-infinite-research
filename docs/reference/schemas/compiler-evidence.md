---
title: "CompilerEvidence Schema"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-11
supersedes: []
superseded_by: []
source_of_truth_for:
  - compiler-evidence-schema
---

# CompilerEvidence Schema

`CompilerEvidence` schema 2 is a target-neutral canonical data object built only after MIR postconditions and output parity succeed. `prototypes/mir/domain/evidence/compiler_evidence.lua` owns the object; publication transport is separate.

The artifact contains `compilation_fingerprint`, `qualification_fingerprint`, the compatibility `semantic_fingerprint` alias, `telemetry_fingerprint`, `run_fingerprint`, deterministic `input_sanitation_ledger` and `output_sanitation_ledger` records, a fingerprint for each ledger, and `evidence_fingerprint` for the complete envelope.

Each affected technology ledger row records the original technology name and effect count, owner kind, owning mod or explicit unknown status, `original_effects_fingerprint`, removed effects with original indexes and full-effect fingerprints, exact retained original order, retained semantic identities, `retained_effects_fingerprint`, and `sanitized_effects_fingerprint`. Both passes also bind the complete inventory of sanitation-covered target prototype families. Output publication fails if MIR created or removed one of those targets after input sanitation.

Factorio 2.1 normal loads publish `more-infinite-research-compiler-evidence` with data type `more-infinite-research.compiler-evidence-public`. The schema-1 public projection contains compilation, qualification, semantic, telemetry, run, and evidence fingerprints; telemetry counts and phases; compact input/output sanitation counts and inventory fingerprints; and the target-inventory parity result.

Public evidence is constructed once from telemetry captured before its own serialization and final byte-budget check. Its `compiler_evidence_public_bytes` and `public_artifact_total_bytes` counters therefore remain unobserved at that boundary; zero does not describe the emitted envelope's size or certify its budget. The live compiler telemetry records those sizes after the exact final check. The preview exporter reports the unavailable self-size as `not-observed`. Compilation and qualification fingerprints retain their gameplay meaning; telemetry, run and envelope fingerprints may change with these diagnostic measurements.

Qualification-snapshot size telemetry uses the same canonical writer with a counting sink. It validates the record and preserves canonical encoding and rejection behavior without retaining a serialized string or invoking the public defensive-copy snapshot API. A requested public snapshot still returns its independent copy.

When generation diagnostics are enabled or automatic compiler preview/report mode requests detailed artifacts, MIR additionally publishes the complete schema-2 object as `more-infinite-research-compiler-evidence-internal` with data type `more-infinite-research.compiler-evidence-internal`. Validation fixtures that inspect individual sanitation ledger rows use this explicit internal surface. A target without `mod-data` uses a validation-log envelope containing the canonical fingerprints. Developer JSON and harness extraction can serialize the internal object without redefining its semantics.
