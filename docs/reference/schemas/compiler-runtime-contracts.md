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

MIR uses explicit, fingerprinted records at capture, compilation, application, and qualification boundaries. Candidate identity is deliberately absent from these contracts; the current candidate is generated from `.mir/releases.json`.

## Implemented data flow

```text
Factorio capture and proposal adapters
  -> CompilationSnapshot schema 1
  -> PolicySnapshot schema 1
  -> RuntimeEnvironmentIdentity schema 2
  -> CompilerInput schema 2
  -> sanitation + graph-qualified TechnologyCatalog schema 3
  -> compiler.compile(CompilationSnapshot, PolicySnapshot)
  -> TransformationPlan schema 1
  -> shared technology operation executor
  -> MutationJournal schema 1
  -> CompilerResult schema 2

external release harness
  -> QualificationEnvironmentIdentity schema 1
```

The capture adapter owns all reads of `data.raw`, startup settings, loaded mods, target APIs, recipe/index services, and active provider discovery. It freezes normalized prototype surfaces, relationship and recipe facts, graph input, target inventory, provider claims, stream proposals, base-continuation proposals, and their derived fingerprints in `CompilationSnapshot`.

`PolicySnapshot` freezes effective settings, compatibility and stream policy, promotion authority, total hard-gate authority, effect contracts, quality profiles, transformation policy, and weapon-overlap mode. `CompilerInput` binds those two snapshots to the exact runtime environment and input-sanitation fingerprint.

`planner/compiler.lua` accepts only `CompilationSnapshot` and `PolicySnapshot`. It does not read Factorio globals, settings, loaded mods, clocks, logging, telemetry, or `CompilerContext`. It validates every proposal's exact total gate vector, rejects or retains review-required alternatives, validates provider-claim identity, and returns a qualified-only `TransformationPlan` made of common create/patch/delete operation envelopes.

The current pipeline retains a compatibility finalization pass before the pure compiler to normalize legacy stream proposals, perform sanitation, and prove the combined graph. That pass does not emit prototypes. The pure compiler consumes the resulting qualification snapshot and is the sole source of executable technology operations. This compatibility seam is explicit in the runtime data flow and may be narrowed without changing the snapshot, plan, operation, or journal contracts.

## Runtime and qualification identity

`RuntimeEnvironmentIdentity` binds the Factorio target, target-profile fingerprint, exact sorted loaded-mod ID/version closure, effective startup settings, imported profile, active compatibility policy, and promotion authority. Runtime equality is exact fingerprint equality.

`QualificationEnvironmentIdentity` belongs to the external release harness. It binds runner, workflow, executable, base data, plan, verifier, trust policy, and evidence scope. It cannot substitute for runtime identity, and runtime identity cannot claim release trust.

## Catalog, result, and mutation truth

The schema-3 `TechnologyCatalog` becomes final only after sanitation and graph proof. It preserves accepted and rejected stream and base-continuation designs with exact qualifications and total hard gates. Final selection accepts only `qualified` alternatives; a proposal is never silently upgraded to a pass.

`CompilerResult` schema 2 reports independent dimensions for execution, safety, review, promotion, and release admission. Its projections include accepted, rejected, review-required, provider-claim, base-continuation, quality, promotion, and sanitation classes, with an exact count and fingerprint for each class. The scalar status is derived from those dimensions and cannot conceal a blocker.

Every materializing stream, base continuation, and native-owner patch becomes a `TransformationOperation`. Operations bind subject, action, precondition, expected output, authority, payload, and evidence fingerprints. The shared technology executor records exact before/after state in `MutationJournal`; duplicate operation IDs and undeclared mutations fail closed.

## Context isolation

`CompilerContext` schema 4 is an explicit lifetime boundary. `new()` does not activate a context. `with_active()` scopes activation and restores the previous context after normal return or error, including nested A/B/A execution. Effective-settings import state and competing-policy preparation are context-owned; no run-derived module cache may survive into another compilation.

## Quality and promotion

Safety, quality, review, promotion, execution, and release admission are separate decisions. Seven schema-2 quality profiles cover existing-stream attachment, native-owner patching, base continuation, new machine manufacturing, new lab manufacturing, exact overhaul material, and experimental process families. Their thresholds and required evidence differ by risk.

A missing quality measurement is `INCOMPLETE` and therefore `REVIEW_REQUIRED`; it is never interpreted as zero. Provider semantic metrics and observational time/memory measurements retain separate provenance. Promotion requires an exact passing assessment, design and claim fingerprints, members/exclusions, ecosystem and settings identity, effect/cost/progression evidence, human approval, applicability envelope, migration decision, upgrade evidence, and promotion fingerprint.

## Compatibility policy

`.mir/compiler-schema-authority.json` defines readable, writable, and compatibility-projection versions. Unknown schema versions fail closed. Schema-1 `CompilerInput`, `CompilerResult`, and runtime-environment views are explicit projections only; they cannot overwrite schema-2 authority.
