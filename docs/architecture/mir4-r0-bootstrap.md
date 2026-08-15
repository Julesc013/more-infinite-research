---
title: "MIR 4 R0 Bootstrap"
status: current
applies_to: "MIR4-R0-pre-release"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# MIR 4 R0 Bootstrap

MIR 3 product development is closed. All nine `.9` releases are immutable and GitHub-published; Mod Portal custody and the archival EOL programme remain open. MIR 4 R0 is active only on the package-excluded successor plane.

The executable authority is `.mir/releases/waves/mir4-r0/`. It separates programme, entry, version, target, equivalence, layout, terminal import, bootstrap roots, emergency-lane, offline release, and governance-reconciliation decisions. The generated dashboard must report `READY_FOR_MIR4_R0_IMPLEMENTATION`, and the generated queue must name `M4-003-local-offline-emergency-lane` as the next executable task.

## Current boundary

```text
MIR 3 GitHub publication: complete
MIR 3 Mod Portal custody: partial; seven .9 uploads absent
MIR 3 product development: closed
MIR 3 final .9 baselines: deterministic capture ready; custody pending
MIR 3 EOL: pending
MIR 4 R0: active, package-excluded, non-authoritative
public 4.x: forbidden until MIR 3 EOL
f210 exact executable lock: unavailable; observed same version/build has a different SHA-256
f200/f110/f100 exact executable locks: observed matching; no MIR 4 candidates admitted
```

The dated non-emitting readiness records refine the earlier environment snapshot without changing the entry gate. Factorio 2.0.77.84539, 1.1.110.62357, and 1.0.0.54889 Windows x86-64 executables match their imported locks. The observed Factorio 2.1.13.87164 executable does not match the required executable SHA-256, so M4-003 exact-engine qualification remains blocked. No official data/module closure or MIR 4 runtime result is claimed by this executable-only observation.

Mod Portal custody also remains fail-closed. A dated read-only recheck confirms that both `3.2.9` and `2.5.9` appear in the official API and the rendered downloads table with API SHA-1 values matching their sealed archives. That public visibility does not substitute for custody: authenticated redownload, byte verification, exact-engine public-asset smoke, archive and rights records, and the MIR 3 EOL seal remain open.

Distribution identity is now owned by `MIR4-Target-RegistryV2` and `MIR4-Versioning-and-Distribution-Identity-ADRv2`. The registry contains all 17 direct string codes from `210` through `006`; the exhaustive codec fixture covers patches `00`, `01`, `08`, `09`, and `99`, the `65499` internal boundary, and negative inputs. The two V1 identity records are preserved byte-for-byte as historical evidence and are rejected by the executable resolver.

`tools/mir.ps1 mir4 check` validates the acyclic entry gate, all ten typed R0 authorities, version projection, nine baseline manifests, nine normalized snapshots, nine release-closure views, the all-nine import, the four-target bootstrap root set, dashboard, queue, and unchanged terminal distributions.

`bootstrap-root-set.json` derives the `f210`, `f200`, `f110`, and `f100` semantic, authority, and qualification roots from the all-nine terminal import. Semantic roots bind only target, predecessor, source, and terminal content identity. Baseline and snapshot records, terminal archive identity, and exact-engine proof remain separately authority- or qualification-bound, so custody-only updates cannot silently change a semantic root.

`tools/mir.ps1 mir4 capture-terminal-baselines --build-bundles` reconstructs each logical terminal bundle twice. The bundles live under `build/terminal/dot9-baselines/`; they are evidence outputs, not public mod packages.

## Architecture direction

MIR 4 promotes the proven MIR 3 fact, compiler, plan, graph, target, stable-ID, migration, and assurance boundaries. It does not introduce a second writable recipe or technology fact system. New authorities begin in shadow, name the imported owner, prove parity and rollback, and cut over one owner at a time.

The eventual layout separates `src/`, `platforms/factorio/`, and `targets/`. Current Factorio package-shaped source remains canonical until generated projections prove exact package and behavior equivalence. No mass move, `src4/` copy, public SDK, or public 4.x artifact is admitted in R0.

## Next slice

The M4-003A identity precondition is closed. The local package-construction portion resolves source proposal `4.0.0`, code `210`, and projected distribution `4.0.21000` through V2. Capsule V2 binds raw package-source Git objects, the exact authority/schema/tool closure, the canonical builder, and the complete executing PowerShell/.NET home. A and B run in distinct child processes; both complete workspaces are deleted; C then runs in a fresh system-temporary root from copied capsule inputs with no checkout argument or inherited checkout working directory. The three receipts and candidate bytes are identical, closing capsule-only checkout-independent C reconstruction. This does not claim a separate OS ACL/container checkout denial or a network-denied runtime campaign. It allocates no public tag. The remaining lane requires exact-engine clean-install and direct-upgrade proof, reload and settings/profile preservation, offline sealing, restoration, and two independently written, byte-identical publication dry runs. Completing that slice does not itself authorize publication.
