---
title: "MIR 4 R0 Bootstrap"
status: current
applies_to: "MIR4-R0-pre-release"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# MIR 4 R0 Bootstrap

MIR 3 product development is closed except for the immutable post-terminal 3.2.10 and 2.5.10 emergency releases. All historical `.9` releases remain immutable; Mod Portal custody and the archival EOL programme remain open. MIR 4 R0 is active only on the package-excluded successor plane.

The executable authority is `.mir/releases/waves/mir4-r0/`. It separates programme, entry, version, target, equivalence, layout, terminal import, bootstrap roots, emergency-lane, offline release, and governance-reconciliation decisions. The generated dashboard reports `READY_FOR_MIR4_R0_IMPLEMENTATION`, and the generated queue names Plan V2 candidate materialization and target-local reproof as the next executable M4-003 task.

## Current boundary

```text
MIR 3 GitHub publication: 3.2.10 Latest; 2.5.10 published and verified
MIR 3 Mod Portal custody: partial; seven .9 uploads absent
MIR 3 product development: closed
MIR 3 final .9 baselines: deterministic capture ready; custody pending
MIR 3 EOL: pending
MIR 4 R0: active, package-excluded, non-authoritative
public 4.x: forbidden until MIR 3 EOL
f210 exact executable lock: Steam Factorio 2.1.14 maintainer lock bound
f200 exact executable lock: Factorio 2.0.77 lock bound to 2.5.10 predecessor
f110/f100 exact executable locks: observed matching
MIR 4 local construction: Plan V2 current; private lane V2 current; candidate reproof pending
```

The dated non-emitting readiness records remain historical evidence. Current predecessor authority binds 3.2.10 to the maintainer-accepted Steam Factorio 2.1.14 executable and 2.5.10 to Factorio 2.0.77. Those locks permit candidate-bound reproof; they do not themselves claim MIR 4 runtime qualification.

Mod Portal custody also remains fail-closed. A dated read-only recheck confirms that both `3.2.9` and `2.5.9` appear in the official API and the rendered downloads table with API SHA-1 values matching their sealed archives. That public visibility does not substitute for custody: authenticated redownload, byte verification, exact-engine public-asset smoke, archive and rights records, and the MIR 3 EOL seal remain open.

Current predecessor identity is owned by `MIR4-Target-RegistryV3`; distribution encoding remains owned by the unchanged `MIR4-Target-RegistryV2` and `MIR4-Versioning-and-Distribution-Identity-ADRv2` codec pair. The registry contains all 17 direct string codes from `210` through `006`; the exhaustive codec fixture covers patches `00`, `01`, `08`, `09`, and `99`, the `65499` internal boundary, and negative inputs. Earlier registry generations remain historical evidence.

`tools/mir.ps1 mir4 check` validates the acyclic entry gate, all ten typed R0 authorities, version projection, nine baseline manifests, nine normalized snapshots, nine release-closure views, the all-nine import, the four-target bootstrap root set, dashboard, queue, and unchanged terminal distributions.

`bootstrap-root-set.json` derives the `f210`, `f200`, `f110`, and `f100` semantic, authority, and qualification roots from the all-nine terminal import. Semantic roots bind only target, predecessor, source, and terminal content identity. Baseline and snapshot records, terminal archive identity, and exact-engine proof remain separately authority- or qualification-bound, so custody-only updates cannot silently change a semantic root.

`tools/mir.ps1 mir4 capture-terminal-baselines --build-bundles` reconstructs each logical terminal bundle twice. The bundles live under `build/terminal/dot9-baselines/`; they are evidence outputs, not public mod packages.

## Architecture direction

MIR 4 promotes the proven MIR 3 fact, compiler, plan, graph, target, stable-ID, migration, and assurance boundaries. It does not introduce a second writable recipe or technology fact system. New authorities begin in shadow, name the imported owner, prove parity and rollback, and cut over one owner at a time.

The eventual layout separates `src/`, `platforms/factorio/`, and `targets/`. Current Factorio package-shaped source remains canonical until generated projections prove exact package and behavior equivalence. No mass move, `src4/` copy, public SDK, or public 4.x artifact is admitted in R0.

## Next slice

Plan V1 and the first private-lane authorization remain historical. `MIR4BootstrapLocalCandidatePlanV2` imports the current terminal import, Target Registry V3, 3.2.10 and 2.5.10 predecessor refresh, and `MIR4ApprovedBootstrapCorrectionDeltaV2`. `MIR4PrivateLaneAuthorizationV2` advances f200 to the immutable 2.5.10 predecessor while retaining f110 and f100 unchanged. The next M4-003 slice is deterministic f210 and f200 construction followed by exact-engine clean-install, direct-upgrade, reload, settings/profile preservation, and MIR3-TERM-0033 rollback reproof. It allocates no public tag and authorizes no public output.
