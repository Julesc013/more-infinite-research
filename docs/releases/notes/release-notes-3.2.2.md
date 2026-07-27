---
title: "MIR 3.2.2 Release Notes"
status: current
applies_to: "3.2.2"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-27
supersedes:
  - docs/releases/notes/release-notes-3.2.1.md
superseded_by: []
---

# MIR 3.2.2

MIR 3.2.2 is an emergency Pyanodons startup-integrity and affected-save planet-discovery recovery hotfix.

## Release artifact

- Package: `dist/more-infinite-research_3.2.2.zip`
- Package source: `7ebe10dd52e34c8df54dc98dbc0f1375a134c4b8`
- Size: `1,030,828` bytes
- Entries: `291`
- SHA-256: `638CF9254915B24824BEA6FD66D420B15CD41876334D32AC2ED5D81136D9A938`
- Content SHA-256: `B2E5745CB6ED6F093509B358FDBC8D64D45F0BE3A7439B65A6A8CD8FAD5CD0C4`
- Compatibility: Factorio `2.1.8` or newer
- Release validation: Factorio `2.1.12`

## Fixed

- Ordered MIR after Pyanodons Post-processing when that mod is enabled.
- Sanitized the finalized Py technology tree after late post-processing reconstructs unlock effects.
- Removed the stale `casting-mk02` unlock for the deleted `casting-gear` recipe while retaining valid sibling effects in their original order.
- Added a one-time `3.2.0`/`3.2.1` to `3.2.2` configuration-change repair for valid researched space locations that remain locked.
- Preserved current research, fractional progress, unrelated technology effects, and already-correct location state.

## Exact scope

- The Py correction is a generic finalizer-order and missing-target sanitation repair, not a hard-coded mutation of `casting-mk02`.
- The compatibility claim is limited to startup integrity for the exact tested reduced Py closure; it is not a broad claim that every Py-generated technology is semantically supported.
- The planet repair runs only for upgrades from MIR 3.2.0 or 3.2.1 to MIR 3.2.2.
- The repair unlocks only valid locations referenced by researched discovery technologies and never performs a force-wide technology-effect reset.

## Upgrade behavior

- Install 3.2.2 and load the affected save normally.
- Researched valid planets left locked by 3.2.0 or 3.2.1 are restored during the configuration change.
- Existing current research, research progress, and unrelated technology state remain intact.

## Qualification status

- Deterministic package reconstruction: passed twice with identical bytes.
- Exact C21-to-C22 package delta: one added runtime repair module and three changed packaged files; no removals.
- Exact ZIP Base and Space Age loads: passed in focused validation.
- Synthetic late Py reconstruction and exact sibling-order sanitation: passed.
- Direct six-row 3.2.1-to-3.2.2 upgrade matrix: pending final candidate-bound rerun.
- Exact reduced Py runtime closure: pending final candidate-bound run.
- Full no-reuse, protected qualification, schema-4 seal, and independent seal check: pending.

Publish only the exact recorded ZIP after every remaining gate passes; do not rebuild it during publication.