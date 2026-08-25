---
title: "MIR 4 R0 Bootstrap"
status: current
applies_to: "MIR4-R0-pre-release"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-25
supersedes: []
superseded_by: []
---

# MIR 4 R0 Bootstrap

MIR 3 product development is closed. The post-terminal 3.2.11 and 2.5.11 releases and all historical `.9` releases remain immutable; unresolved alias/hotfix PR residue and remaining custody work are tracked separately. MIR 4 R0 is active only on the package-excluded successor plane.

The current executable authority is `.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Execution-ProgrammeV1.json`. It binds the exact Dev baseline, current release cut, workflow maturity vocabulary, blocker authorities, MIR 3 residual disposition, and 22-turn dependency queue. The generated dashboard reports `T02-COMPLETE-T03-T04-READY-RELEASE-BLOCKED`; source-freeze/target-build adapters and qualification/preview/independent-verification adapters are now the dependency-ready work packages.

## Current boundary

```text
MIR 3 GitHub publication: 3.2.11 Latest; 2.5.11 published and verified
MIR 3 open PR residue: PR 149 alias advance and draft PR 146 require disposition
MIR 3 product development: closed
MIR 4 R0: active, package-excluded, non-authoritative
MIR 4 candidate: pre-freeze, M4RC1 unallocated
f210 exact executable lock: Steam Factorio 2.1.14 maintainer lock bound
f200 exact executable lock: Factorio 2.0.77 lock bound to 2.5.11 predecessor
release phase kernel: event-sourced, idempotent, resumable, tested, non-production only
release workflows: 10 registered and fail-closed; 0 phase adapters implemented or rehearsed
source freeze, signing, promotion, tags and publication: blocked
```

The dated non-emitting readiness records remain historical evidence. Current predecessor authority binds 3.2.10 to the maintainer-accepted Steam Factorio 2.1.14 executable and 2.5.10 to Factorio 2.0.77. Those locks permit candidate-bound reproof; they do not themselves claim MIR 4 runtime qualification.

Mod Portal custody also remains fail-closed. A dated read-only recheck confirms that both `3.2.9` and `2.5.9` appear in the official API and the rendered downloads table with API SHA-1 values matching their sealed archives. That public visibility does not substitute for custody: authenticated redownload, byte verification, exact-engine public-asset smoke, archive and rights records, and the MIR 3 EOL seal remain open.

Current target identity is owned by `MIR4-Target-RegistryV6`; distribution encoding remains owned by the unchanged V2 codec authority. Earlier registry generations remain historical evidence.

`tools/mir.ps1 mir4 check` validates the acyclic entry gate, all ten typed R0 authorities, version projection, nine baseline manifests, nine normalized snapshots, nine release-closure views, the all-nine import, the four-target bootstrap root set, dashboard, queue, and unchanged terminal distributions.

`bootstrap-root-set.json` derives the `f210`, `f200`, `f110`, and `f100` semantic, authority, and qualification roots from the all-nine terminal import. Semantic roots bind only target, predecessor, source, and terminal content identity. Baseline and snapshot records, terminal archive identity, and exact-engine proof remain separately authority- or qualification-bound, so custody-only updates cannot silently change a semantic root.

`tools/mir.ps1 mir4 capture-terminal-baselines --build-bundles` reconstructs each logical terminal bundle twice. The bundles live under `build/terminal/dot9-baselines/`; they are evidence outputs, not public mod packages.

## Architecture direction

MIR 4 promotes the proven MIR 3 fact, compiler, plan, graph, target, stable-ID, migration, and assurance boundaries. It does not introduce a second writable recipe or technology fact system. New authorities begin in shadow, name the imported owner, prove parity and rollback, and cut over one owner at a time.

The eventual layout separates `src/`, `platforms/factorio/`, and `targets/`. Current Factorio package-shaped source remains canonical until generated projections prove exact package and behavior equivalence. No mass move, `src4/` copy, public SDK, or public 4.x artifact is admitted in R0.

## Next slice

The former M4-003 bootstrap queue is retained as historical evidence. T02 now provides the package-excluded, event-sourced release phase kernel with an explicit phase interface, idempotency, resume, compensation, receipts, and bounded Git, build, engine, signing, and publication ports. It authorizes no production mutation. T03 and T04 add the first phase adapters without changing that production boundary.
