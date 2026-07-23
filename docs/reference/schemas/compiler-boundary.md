---
title: "Compiler Boundary Schemas"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Compiler Boundary Schemas

`planner/compiler.lua` exposes the pure API `compile(snapshot, policy)`. It does not read Factorio globals, startup settings, loaded mods, clocks, telemetry, logging, or `CompilerContext`.

| Record | Schema | Authority |
| --- | ---: | --- |
| `CompilationSnapshot` | 1 | Normalized prototype surfaces, facts, graph input, target inventory, and candidate inputs |
| `PolicySnapshot` | 1 | Effective settings, compatibility, streams, gates, targets, quality, promotion, and mutation policy |
| `CompilerInput` | 2 | Exact compilation, policy, runtime environment, sanitation, and source fingerprints |
| `CompilerResult` | 2 | Execution, safety, review, promotion, release, and complete disposition projections |
| `RuntimeEnvironmentIdentity` | 2 | Runtime target, exact mods, effective settings/import, policy, and promotion authority |
| `QualificationEnvironmentIdentity` | 1 | Candidate, Factorio binary, runner, verifier, test set, plan, and trust class |
| `TransformationOperation` | 1 | One create, patch, or delete with precondition, payload, expected output, authority, and evidence |
| `TransformationPlan` | 1 | Canonically ordered qualified operations bound to snapshot and policy |
| `MutationJournal` | 1 | One before/after/status record per applied operation |

## Gate closure

Every candidate contains exactly the gates in `.mir/technology-hard-gates.json`. Missing and unknown keys fail validation. A `not-applicable` gate is authoritative only with an evaluator, applicability predicate, exact input fingerprint, false result, evidence, and evidence fingerprint. Final selection excludes proposals.

## Compatibility

`.mir/compiler-schema-authority.json` declares readable and writable versions. Unknown versions fail closed. CompilerInput, CompilerResult, and RuntimeEnvironmentIdentity schema 2 expose explicit schema-1 projections; projected fingerprints never replace authoritative fingerprints.

## Replay and mutation

The same serialized snapshot and policy must produce the same compilation and transformation-plan fingerprints in a fresh process and under randomized map insertion order. Executors consume the exact transformation operation and write its result to the mutation journal. Re-evaluating ambient engine state inside the pure compiler is forbidden.
