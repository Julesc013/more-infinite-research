---
title: "Compiler Runtime Contracts"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-24
supersedes: []
superseded_by: []
---

# Compiler Runtime Contracts

MIR uses explicit, fingerprinted records at capture, compilation, application, and qualification boundaries. Candidate identity is deliberately absent from these contracts; the current candidate is generated from `.mir/releases.json`.

## Implemented data flow

```text
Factorio capture and proposal adapters
  -> CompilationSnapshot schema 2
  -> PolicySnapshot schema 1
  -> RuntimeEnvironmentIdentity schema 2
  -> CompilerInput schema 2
  -> sanitation + graph-qualified TechnologyCatalog schema 3
  -> compiler.compile(CompilationSnapshot, PolicySnapshot)
  -> TransformationPlan schema 2
  -> shared technology operation executor
  -> MutationJournal schema 2
  -> CompilerResult schema 3 (planned -> final)

external release harness
  -> QualificationEnvironmentIdentity schema 1
```

The capture adapter owns every read of `data.raw`, startup settings, loaded mods, target APIs, recipe/index services, and active provider discovery. It normalizes recipes, technologies, items, entities, labs, and science packs into immutable fact domains. Each domain has its own fingerprint. Relationship, owner, graph, effect-target, provider, stream, and base-continuation inputs have independent fingerprints, and the top snapshot fingerprint binds those identities as a Merkle-style root.

The qualification snapshot structurally shares unchanged fact domains and indexes with the input snapshot. Only stream and base-continuation qualification material is replaced. Compact snapshots contain fingerprints, sharing metadata, and metrics; a full deep projection is explicit diagnostic work, never the normal public artifact path.

`PolicySnapshot` freezes effective settings, compatibility and stream policy, promotion authority, total hard-gate authority, effect contracts, quality profiles, transformation policy, weapon-overlap mode, compiler execution mode, and review policy. `CompilerInput` binds those snapshots to the exact runtime environment and input-sanitation fingerprint. Finalization reads this captured policy only; unrelated live-policy mutation cannot change the result.

Execution modes are explicit. `SAFE` and `PREVIEW` retain review-required proposals without aborting startup. `STRICT_CI` and `RELEASE` fail unless their captured policy explicitly authorizes the review state. `REVIEWED` applies its captured reviewed-mode rule. `PREVIEW` additionally publishes full internal diagnostic artifacts. Unknown mode names fail closed. The pipeline entry point forwards its `execution_mode` option into the context, so validation and release adapters can select strict modes without changing package policy; ordinary startup omits the option and remains `SAFE`.

`planner/compiler.lua` accepts only `CompilationSnapshot` and `PolicySnapshot`. It does not read Factorio globals, settings, loaded mods, clocks, logging, telemetry, or `CompilerContext`. It validates every proposal's exact total gate vector, rejects or retains review-required alternatives, validates provider-claim identity, and returns one mandatory `TransformationPlan` made only of exact create and patch envelopes. There is no optional operation path and no public per-operation mutation API.

The current pipeline retains a compatibility finalization pass before the pure compiler to normalize legacy stream proposals, perform sanitation, and prove the combined graph. That pass does not emit prototypes. The pure compiler consumes the resulting qualification snapshot and is the sole source of executable technology operations. This compatibility seam is explicit in the runtime data flow and may be narrowed without changing the snapshot, plan, operation, or journal contracts.

## Runtime and qualification identity

`RuntimeEnvironmentIdentity` binds the Factorio target, target-profile fingerprint, exact sorted loaded-mod ID/version closure, effective startup settings, imported profile, active compatibility policy, and promotion authority. Runtime equality is exact fingerprint equality.

`QualificationEnvironmentIdentity` belongs to the external release harness. It binds runner, workflow, executable, base data, plan, verifier, trust policy, and evidence scope. It cannot substitute for runtime identity, and runtime identity cannot claim release trust.

## Catalog, result, and mutation truth

The schema-3 `TechnologyCatalog` becomes final only after sanitation and graph proof. It preserves accepted and rejected stream and base-continuation designs with exact qualifications and total hard gates. Final selection accepts only `qualified` alternatives; a proposal is never silently upgraded to a pass.

`CompilerResult` schema 3 has two immutable phases. The planned result binds the compiler input, catalogs, plans, qualifications, operation membership, and independent execution, safety, review, promotion, and release dimensions. Finalization creates a new final result; it never mutates the planned record. The final record binds the planned-result fingerprint, realized output, journal, graph parity, sanitation parity, planned/executed/skipped/failed operation counts, and `APPLIED` or `FAILED` execution status. Any skipped mandatory operation or terminal-count mismatch fails execution. The scalar status is derived from those dimensions and cannot conceal a blocker.

Every materializing stream, base continuation, and native-owner patch becomes one schema-2 `TransformationOperation`. Each operation binds its candidate and selected alternative, subject, action, exact expected-before snapshot, exact expected-after projection, allowed delta, qualification, authority, payload, and evidence. The schema-2 plan binds canonical operation order and membership fingerprints. The shared technology executor applies that exact plan and records realized before/after state in its plan-bound schema-2 `MutationJournal`. Missing, duplicate, undeclared, fingerprint-mismatched, precondition-mismatched, postcondition-mismatched, failed, and out-of-plan operations fail closed.

## Public artifact and telemetry boundary

Normal loads publish compact schema-1 generation-plan, technology-catalog, coverage, and compiler-evidence projections. Full catalog candidates, alternatives, qualifications, and internal evidence are available only in `PREVIEW`, diagnostics-enabled validation, or exact offline exports. The compact catalog carries counts, selected identities, reason histograms, provider summaries, bounded samples, and explicit truncation markers; it does not carry full candidates or qualifications.

`.mir/public-artifact-budgets.json` governs hard canonical-byte limits and the runtime budget module mirrors that authority. Generation-plan public data is limited to 512 KiB. Catalog, coverage, and compiler-evidence public artifacts are each limited to 128 KiB. Exceeding a limit aborts publication and fails validation. Telemetry records public/internal bytes, normalized snapshot bytes, source prototype bytes captured, structural sharing, copied domains, canonicalization passes, construction time, and peak-memory observations.

## Context isolation

`CompilerContext` schema 4 is an explicit lifetime boundary. `new()` does not activate a context and there is no public `activate` function. `with_active()` uses packed protected calls, preserving nil-position and multiple return values while restoring the previous context after normal return or traceback-bearing error, including nested A/B/A execution. Effective-settings import state and competing-policy preparation are context-owned; no run-derived module cache may survive into another compilation.

## Quality and promotion

Safety, quality, review, promotion, execution, and release admission are separate decisions. Seven schema-2 quality profiles cover existing-stream attachment, native-owner patching, base continuation, new machine manufacturing, new lab manufacturing, exact overhaul material, and experimental process families. Their thresholds and required evidence differ by risk.

A missing quality measurement is `INCOMPLETE` and therefore `REVIEW_REQUIRED`; it is never interpreted as zero. Provider semantic metrics and observational time/memory measurements retain separate provenance. Promotion requires an exact passing assessment, design and claim fingerprints, members/exclusions, ecosystem and settings identity, effect/cost/progression evidence, human approval, applicability envelope, migration decision, upgrade evidence, and promotion fingerprint.

## Compatibility policy

`.mir/compiler-schema-authority.json` defines readable, writable, and compatibility-projection versions. Unknown schema versions fail closed. CompilerInput and RuntimeEnvironmentIdentity schema-1 views and the CompilerResult schema-2 view are explicit compatibility projections only; they cannot overwrite schema-2 input/environment or schema-3 result authority.
