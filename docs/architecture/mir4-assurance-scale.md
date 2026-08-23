---
title: "MIR 4 Assurance Scale and Offline Drill"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-23
supersedes: []
superseded_by: []
---

# MIR 4 assurance scale and offline drill

W08 adds a package-excluded, read-only projection over the two existing assurance systems. Control Plane v5 remains authoritative for semantic reads and writes, transitive impact, evidence objects, freshness, revocation, execution and aggregate release gates. Assurance v4 remains authoritative for its verification plans, exact trusted reuse, workers, checkpoints, capsules and aggregate evidence. W08 does not create another evidence ledger or scheduler.

## Four identities

The projection names four independent stages:

- `CaptureKey` is the Control Plane observation capture identity, extended with references to the eleven slice roots.
- `CompilationKey` binds exact snapshot and policy references, target and compiler ABI.
- `RealizationKey` binds accepted plans, candidate content, target and executor reference.
- `EvaluationKey` is produced by the Control Plane evaluator from the observation, assertion and evaluator ABI.

A compilation-only change does not invalidate capture, realization or evaluation. A realization-only change does not invalidate the other three. An evaluator ABI change invalidates only evaluation. A capture change also invalidates its downstream evaluation.

## Observation slices

The fixed slice set is recipe facts, ProcessIR, technology graph, science/lab graph, ownership, settings, runtime state, diagnostics, presentation, locale and package identity. Available slices contain sorted authority-reference leaves and a deterministic Merkle root. An absent authoritative observation is represented as `unavailable` with no fabricated digest. The current exact-target ProcessIR snapshot therefore remains `BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT`.

## Impact, reuse and proof cover

W08 calls the Control Plane semantic impact graph and mutation calibration rather than reimplementing them. Unknown ownership retains `select-all-and-fail-governance`, and the false-negative budget remains zero. Recovery reuses work only when identity, candidate, target, ABI and trust match exactly and the evidence is passing and unrevoked. Conflicting outcomes for one identity create a blocking nondeterminism incident. Counterexample reduction retains the target, evidence and safety constraints.

Proof-cover planning is proposal-only. It may combine proof candidates only when target, environment and trust all match the obligation. Every mandatory obligation remains covered; an uncovered obligation blocks. The projection cannot edit the active verification selector or schedule work.

## The 24/6/1 design model

The deadline classes are minor 24 hours with an 18-hour design p95, patch 6 hours with a 4-hour-30-minute design p95, and hotfix 1 hour with a 45-minute design p95. The budget record reports affected targets, fresh and reused proof, critical path, estimates, headroom, manual requirements and worker capacity.

These are design targets, not release claims. Without trusted timing and capacity evidence, the official W08 rows remain `BLOCKED-MISSING-TIMING-EVIDENCE` and `BLOCKED-MISSING-WORKER-CAPACITY-EVIDENCE`. Synthetic fixtures test the arithmetic but cannot certify a deadline.

## Offline and publisher drill

The drill uses only prebuilt non-production fixtures and an isolated path under `build/mir4`. It restores a dummy repository snapshot, constructs a deterministic dummy package, validates a dummy qualification DAG, exercises a non-cryptographic fixture proof verifier, rehearses a non-production seal record, exports a capsule and simulates local-file and LAN-file distribution.

The dummy publisher receives only `inbox`, `verified`, `outbox` and `receipt` roots. It has no build, mutation, source, real-candidate, Factorio, git, credential, production-key, network, seal, promotion, tag, upload or publication capability. It verifies bytes before transfer. Exact pre-existing destination bytes reconcile idempotently; different bytes block.

The drill does not freeze source, allocate an RC, create a production signature or seal, mutate release state, publish or upload. Its records are developer-preview or shadow design artifacts and remain outside every player ZIP.

## Outputs and rollback

`Export-MIR4AssuranceScaleRecords.ps1` writes three source-bound records beneath `build/mir4/m4c02-assurance-scale`:

- `MIR4_ASSURANCE_SCALE_RESULT.json`
- `MIR4_RELEASE_BUDGET_PLAN.json`
- `MIR4_OFFLINE_DRILL_RESULT.json`

Rollback removes only the W08 programme, tooling, schemas, fixtures, documentation, validation and ignored build output. It leaves Control Plane v5, Assurance v4, evidence indexes, candidates, source, packages and release governance unchanged.
