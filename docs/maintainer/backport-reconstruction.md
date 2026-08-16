---
title: "Deterministic Backport Reconstruction"
status: current
applies_to: "MIR 3 terminal .9 target projections"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: []
---

# Deterministic Backport Reconstruction

MIR lower-target releases use an explicit dual-parent integration boundary. The first parent preserves the exact target-line predecessor. The second parent is the immutable canonical source tag whose portable corrections are being projected. The result is independently reconstructed and qualified on its own Factorio engine.

For the terminal wave:

```text
first parent  = exact target .5 tag commit
second parent = immutable 3.2.9 tag commit
tree          = exact admitted target .9 candidate tree
```

The source and target tags must be annotated and immutable. A temporary audit or candidate branch may help qualify a projection, but its head is not the release identity and must not become the only source of reconstruction authority.

## Contract

Before materialization, the target-specific manifest must bind:

- source and target tags and commits;
- direct predecessor ancestry;
- expected integration tree;
- every adapted, omitted, and unchanged package path;
- exact archive and normalized-content SHA-256 values;
- byte and entry counts;
- settings, feature, omission, migration, and package-composition inventories;
- target capability profile and exact engine identity;
- candidate identity and target-tier qualification obligations.

Every modern-to-target difference must be classified as `shared-unchanged`, `shared-with-target-adapter`, `target-only`, `source-only`, `release-evidence-only`, or `intentionally-excluded`. An unclassified package path is a hard stop.

## Rehearsal

Use the existing target materializer with the exact target manifest in a disposable worktree. The materializer must verify both immutable parents, construct the target-first/source-second integration, reapply the admitted tree, build deterministically, compare package identities, and write a reconstruction receipt.

Delete the disposable worktree and repeat from the immutable authorities before sealing. Both rehearsals must produce the same integration commit material, tree, archive identity, content identity, and inventory. Observation timestamps may differ; deterministic receipt material may not.

## Evidence boundary

Portable behavior evidence may be rebound only through exact source-tree and package identity. Runtime, upgrade or transition, performance, manual, protected, seal, tag, and public-asset evidence remains target-specific. Factorio 2.1 proof never substitutes for a lower engine load.

For `2.5.9`, the target predecessor is `2.5.5` and the promoted branch is `legacy`. For `1.9.9` through `1.3.9`, create the deterministic integration and immutable tag without turning historical target worktrees into permanent public branches. `1.8.9` targets Factorio 1.0 only.

Historical `2.5.0` reconstruction remains recorded in `.mir/releases/backports/2.5.0.json`; it is precedent, not the current target contract.
