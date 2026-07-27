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
- Package source: `29f81addc0eec9b571afd6428c9e3529c4497a1b`
- Size: `1,030,817` bytes
- Entries: `291`
- SHA-256: `8A08758EECEEE3A930DE58A36395DD011F9BC2FB69D214CCAFFC065276ECF8D8`
- Content SHA-256: `25E05F748E5B33748F16F78C66DDE4FD11CB48DB5F499BBE232668746981C87F`
- Compatibility: Factorio `2.1.8` or newer
- Minimum-version qualification: exact Factorio `2.1.8` Base and Space Age ZIP loads passed.
- Release validation: Factorio `2.1.12`

## Fixed

- Ordered MIR after Pyanodons Post-processing when that mod is enabled.
- Sanitized the finalized Py technology tree after late post-processing reconstructs unlock effects.
- Removed the stale `casting-mk02` unlock for the deleted `casting-gear` recipe while retaining valid sibling effects in their original order.
- Added a one-time `3.2.0`/`3.2.1` to `3.2.2` configuration-change repair for valid researched space locations that remain locked.
- Preserved current research, fractional progress, unrelated technology effects, and already-correct location state.

## Exact scope

- The Py correction is a generic finalizer-order and missing-target sanitation repair, not a hard-coded mutation of `casting-mk02`.
- The compatibility claim is limited to startup integrity for the exact tested Py Alien Life trigger closure; it is not a broad claim that every Py-generated technology is semantically supported.
- The planet repair runs only for upgrades from MIR 3.2.0 or 3.2.1 to MIR 3.2.2.
- The repair unlocks only valid locations referenced by researched discovery technologies and never performs a force-wide technology-effect reset.

## Upgrade behavior

- Install 3.2.2 and load the affected save normally.
- Researched valid planets left locked by 3.2.0 or 3.2.1 are restored during the configuration change.
- Existing current research, research progress, and unrelated technology state remain intact.

## Qualification status

- Deterministic package reconstruction: passed twice with identical bytes.
- Exact C21-to-C24 package delta: one added runtime repair module and three changed packaged files; no removals.
- Exact ZIP Base and Space Age loads: passed in focused validation.
- Synthetic late Py reconstruction and exact sibling-order sanitation: passed.
- Direct six-row 3.2.1-to-3.2.2 upgrade matrix: passed for Base, Space Age native owners, automatic families, base continuations, mod-set changes, and affected planet discovery.
- Exact paired 3.2.1-to-3.2.2 performance campaign: passed all ten total-load and compiler-phase lanes without changing the governed budgets.
- Exact 15-mod Py 3.1 trigger closure: passed on Factorio 2.1.12 with `casting-gear` and its dangling unlock absent, all valid effects retained, and zero unexpected sanitation.
- Full no-reuse, protected qualification, schema-4 seal, and independent seal check: pending.

Publish only the exact recorded ZIP after every remaining gate passes; do not rebuild it during publication.