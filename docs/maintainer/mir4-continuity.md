---
title: "MIR 4 Continuity, Incident, and Successor Operations"
status: current
applies_to: "MIR 4.0.0+"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-26
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-continuity-incident-successor-runbook
---

# MIR 4 continuity, incident, and successor operations

## Offline restore

Restore the Git bundle or source archive into a clean path, verify commit/tree identities, restore external immutable artifacts by manifest, supply target-local engines and mod closures, regenerate all projections, run the assurance profile, rebuild only unsealed candidates, and compare every output digest. Record a new restore receipt.

## Incident and revocation

Stop the affected phase, preserve bytes and logs, classify the compromised authority, append an incident event, and revoke or rotate credentials outside the repository. Publish revocation metadata through the same independently verified channel. Never delete or rewrite the original receipt.

## Repository fixed point

Move an authority from `.mir` only after all readers, writers, tests, package roots, rollback paths, and independent audit use the visible destination. Decompose by domain rather than renaming `.mir` into another catch-all. Package parity and one-emitter ownership remain gates throughout the incremental cutover.

## Successor or fork

Give the successor public verification material, exact state and archive inventories, current blockers, and the first dependency-ready task. Transfer protected secrets only in a separate ceremony. The successor performs an independent restore and records new custody before operating a release.
