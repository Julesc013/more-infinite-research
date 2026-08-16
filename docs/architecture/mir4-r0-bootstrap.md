---
title: "MIR 4 R0 Bootstrap"
status: current
applies_to: "MIR4-R0-pre-release"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes:
  - docs/architecture/current-architecture-matrix.md
superseded_by: []
---

# MIR 4 R0 Bootstrap

MIR 3 product development is closed. All nine `.9` releases are immutable and GitHub-published; Mod Portal custody and the archival EOL programme remain open. MIR 4 R0 is active only on the package-excluded successor plane.

The executable authority is `.mir/releases/waves/mir4-r0/`. It separates programme, entry, version, target, equivalence, layout, terminal import, emergency-lane, offline release, and governance-reconciliation decisions. The generated dashboard must report `READY_FOR_MIR4_R0_IMPLEMENTATION`, and the generated queue must name `M4-003-local-offline-emergency-lane` as the next executable task.

## Current boundary

```text
MIR 3 GitHub publication: complete
MIR 3 Mod Portal custody: partial; seven .9 uploads absent
MIR 3 product development: closed
MIR 3 final .9 baselines: deterministic capture ready; custody pending
MIR 3 EOL: pending
MIR 4 R0: active, package-excluded, non-authoritative
public 4.x: forbidden until MIR 3 EOL
```

`tools/mir.ps1 mir4 check` validates the acyclic entry gate, all ten typed R0 authorities, version projection, nine baseline manifests, nine normalized snapshots, nine release-closure views, the all-nine import, dashboard, queue, and unchanged terminal distributions.

`tools/mir.ps1 mir4 capture-terminal-baselines --build-bundles` reconstructs each logical terminal bundle twice. The bundles live under `build/terminal/dot9-baselines/`; they are evidence outputs, not public mod packages.

## Architecture direction

MIR 4 promotes the proven MIR 3 fact, compiler, plan, graph, target, stable-ID, migration, and assurance boundaries. It does not introduce a second writable recipe or technology fact system. New authorities begin in shadow, name the imported owner, prove parity and rollback, and cut over one owner at a time.

The eventual layout separates `src/`, `platforms/factorio/`, and `targets/`. Current Factorio package-shaped source remains canonical until generated projections prove exact package and behavior equivalence. No mass move, `src4/` copy, public SDK, or public 4.x artifact is admitted in R0.

## Next slice

M4-003 will generate a local unpublished Factorio 2.1 distribution from the 3.2.9 baseline, double-build it, run clean-install and direct-upgrade proof, verify reload and settings/profile preservation, seal it offline, and dry-run publication twice. Completing that slice does not itself authorize publication.
