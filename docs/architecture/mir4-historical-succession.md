---
title: "MIR 4 Historical, Museum, and Successor-Host Closure"
status: current
applies_to: "4.0.0 M4C02-09-24H"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-08-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-w09-historical-museum-matrix
  - mir4-offline-module-index-and-external-provider-conformance
  - mir4-synthetic-successor-host-proof
  - mir4-append-only-package-succession-witness
---

# MIR 4 Historical, Museum, and Successor-Host Closure

Status: developer-preview shadow evidence for W09 (`M4C02-09-24H`). This module is package-excluded and is not release authority.

## Ownership

W09 composes evidence owned elsewhere. Target identity and disposition remain with Target Registry V6 and the W02 target compiler. Historical archive construction remains with `New-MIR4HistoricalPrivateCandidate.ps1`; exact historical runtime remains with its dedicated runtime harness. Museum source generation remains with `MuseumCompiler.psm1`. Extension closure and transports remain W05-owned, continuity remains W04-owned, and freshness/revocation remains W08-owned.

The W09 module owns only two output projections: `MIR4_HISTORICAL_MUSEUM_MATRIX.json` and `MIR4_SUCCESSOR_HOST_RESULT.json`. The latter embeds the append-only package succession witness. Neither output feeds back into an upstream owner.

The canonical package-excluded applications are `tools/mir/application/history/HistoricalSuccession.ps1` and `tools/mir/application/history/SuccessorHost.ps1`; `tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1` is their canonical exporter. The former `tools/lib/mir4` and `tools/commands/mir4` paths are one-line read-only compatibility forwarders. The accepted historical-tooling receipt and writer are now immutable predecessors. Release-DAG validation remains outside the historical family and is owned by the separate package-excluded `tools/mir/application/release/ReleaseDag.ps1` cutover.

## Historical and museum matrix

The matrix inventories f018 through f013 as private experimental candidates. It checks the exact predecessor archive and snapshot bindings, observes preserved-engine hashes without embedding workstation paths, and imports a fresh runtime receipt only when the dedicated harness has produced one. f018 remains `BLOCKED-MISSING-EXACT-ENGINE` when the governed 0.18 engine lock is unavailable.

For f012 through f006, the matrix records technical archive and exact-engine availability while retaining Target Registry V6's `deferred-museum` disposition. Local possession and deterministic reconstruction do not prove redistribution rights, durable custody, mirrors, or restoration closure. All seven therefore retain `BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE` and are not MIR4 products.

## Offline module and successor proof

The successor-host proof consumes the W05 data-only extension envelope and deterministic closure without adding callbacks or an online registry. The reviewed local index is stable-sorted, hash-bound, and byte-budgeted. A synthetic external f300 provider exercises W02-owned-field locality, idempotence, determinism, unowned-field preservation, and negative forbidden-write behavior.

The synthetic host imports a canonical copy of the W04 continuity bundle, checks redaction, projects the W05 transport as data-only, deterministically replays proof facts, rejects a tampered vector, and reconstructs two byte-identical synthetic archives. These results are conformance fixtures only. They do not establish a future production host or an independent production consumer.

## Succession witness

The embedded witness preserves the immutable 3.2.11/C35 identity and states that its proof remains valid for that release. MIR4 has a different package-source fingerprint, introduced by the recorded 14-root change set, so C35 proof cannot be transferred. The active revocation ledger is not rewritten and C35 is not falsely declared revoked. Candidate-, target-, evaluator-, and ABI-bound inherited evidence requires exact revalidation.

## Firewall and rollback

W09 cannot mutate prototypes, runtime state, migration state, target policy, museum admission, custody rights, immutable release records, revocation state, or player-package bytes. It cannot freeze source, sign, seal, promote, tag, upload, publish, or make a public support claim. Rollback removes only W09 authority, tooling, fixtures, schemas, documentation, and build projections.
