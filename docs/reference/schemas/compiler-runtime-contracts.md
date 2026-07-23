---
title: "Compiler Runtime Contracts"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Compiler Runtime Contracts

MIR C8 gives compilation four explicit, fingerprinted records. They replace implicit tables and inferred process state at the compiler boundary.

## Contract chain

```text
Factorio adapters
  -> EnvironmentIdentity schema 1
  -> CompilerInput schema 1
  -> pure CompilationPlan finalization
  -> TechnologyCatalog schema 3
  -> CompilerResult schema 1
  -> compiler orchestrator
  -> emission and exact artifact publication
```

`CompilerInput` is an immutable snapshot of the requested streams, source fingerprints, configuration, and exact environment. `CompilerResult` is an immutable snapshot of accepted operations, rejected operations, the canonical catalog, and the linked GenerationPlan, CompilationPlan, qualification, input, and result fingerprints. Callers receive defensive copies; mutating a caller-owned input after construction cannot alter either contract.

`EnvironmentIdentity` binds the Factorio target line, target-profile fingerprint, sorted exact loaded-mod ID/version closure, fixture profile when applicable, and configuration fingerprint. Environment equality is fingerprint equality, not a best-effort comparison of selected mod names.

`ProviderMetrics` schema 1 is the authority for provider measurements. Every record binds provider ID/version, family ID, semantic partition, exact environment, candidate dispositions, cluster counts, unlock-depth range, ownership conflicts, cross-version status, phase time, canonical bytes, witnesses, and per-metric provenance. A measurement is `COMPLETE` only when every required metric is measured. Missing measurements remain `INCOMPLETE`; they are never replaced with zero.

## Canonical catalog timing

The schema-3 `TechnologyCatalog` becomes canonical only after sanitation and graph qualification. It preserves accepted and rejected `TechnologyDesign` alternatives, resolves every hard gate to a total authoritative state, and binds exact GenerationPlan and CompilationPlan fingerprints. The GenerationPlan and CompilationPlan must be exact projections of its selected alternatives.

`Export-MIRTechnologyCatalog.ps1` validates and copies this exact artifact byte-for-byte. It cannot rebuild catalog semantics from PowerShell.

## Ownership boundaries

- `pipeline/compiler_orchestrator.lua` owns sequencing and context state.
- `planner/compilation_plan.lua` is a pure finalizer and imports no emitter.
- `integrity/technology_effects.lua` is the planner-safe effect validation service.
- only emission modules mutate prototypes or publish `mod-data`.
- `.mir/module-dependencies.json` is the exact schema-2 cross-layer matrix; no dependency exception is permitted.

Provider ambiguity fails closed as `REVIEW_REQUIRED`. The compiler retains the evidence and rejects attachment; it does not crash and does not guess. Researchability indexing is iterative, so deeply nested or very wide prerequisite graphs do not depend on the Lua call stack.

## Quality interpretation

`TechnologyQualityAssessment` schema 2 requires an exact governed `ProfileId`, metric provenance, and completeness. Status severity is monotonic:

```text
PASS < REVIEW_REQUIRED < FAIL
```

Adding evidence may complete an assessment, but adding a failure cannot improve its status. An incomplete assessment is always `REVIEW_REQUIRED` and cannot satisfy promotion admission.

