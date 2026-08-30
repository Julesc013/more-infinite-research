---
title: "MIR 4 M4C01 Candidate Runbook"
status: current
applies_to: "MIR 4.0.0 M4C01"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir4-m4c01-execution-order
  - mir4-production-authorization-boundary
---
# MIR 4 M4C01 Candidate Runbook

M4C01 integrates developer-preview and shadow-platform surfaces without granting publication or authoritative compiler cutover.

## Order

1. Run platform generation and conformance.
2. Materialize the exact verification plan before tests.
3. Run narrow static gates, then the repository static profile.
4. Build deterministic A/B/C player candidates from exact terminal packages.
5. Run exact-engine fresh-load, direct-upgrade, and two-reload proofs per target.
6. Record manual disposable-profile acceptance independently.
7. Freeze a candidate commit only after f210 and f200 are green; conditionally admit older targets.

## Target boundary

f210 and f200 are mandatory. f110 and f100 are independently conditional. f018 through f013 are private experimental projections and never inherit a support claim from their predecessors. A missing engine or failed lane produces an explicit unqualified status and does not become a pass.

Build and check all target archives before runtime work:

```powershell
.\tools\mir.ps1 mir4 check-historical-private --target all
.\tools\mir.ps1 mir4 check-m4c01-player-set
```

When an exact preserved engine is available, run the private historical direct-upgrade load harness:

```powershell
foreach ($target in 'f017','f016','f015','f014','f013') {
  .\tools\mir.ps1 mir4 runtime-historical-private --target $target
}
```

The harness proves the exact engine and predecessor fingerprints, creates a predecessor save, then performs three bounded candidate loaded-map starts. These repeated starts are useful private evidence but deliberately do not satisfy the independent admission requirement for two persisted upgraded-save reloads. Factorio 0.x also normalizes padded patch components in its log (`4.0.01700` is displayed as `4.0.1700`); the archive name and `info.json` remain bound to the padded distribution identity.

Export one hash-verified status packet after builds, preview packaging and runtime work:

```powershell
.\tools\mir.ps1 mir4 handoff-m4c01
```

The exporter writes `MIR4_M4C01_STATUS.json` and `MIR4_M4C01_HANDOFF.md` beneath `build/mir4/m4c01-handoff`. It records incomplete human, performance, historical reload and production gates as blockers instead of converting them to passes.

The private mandatory-target performance campaigns are `.mir/performance-campaigns/4.0.21000-M4C01.json` and `.mir/performance-campaigns/4.0.20000-M4C01.json`. They compare the exact candidates against `3.2.11` and `2.5.11` respectively. f210 runs six Factorio/compatibility lanes; f200 runs five and records Space Age as omitted by target capability. Both run four compiler phases. These campaigns are development evidence only and cannot substitute for fresh production qualification over a frozen release commit.

The performance runner resolves a line-specific library from `MIR_TESTMODS_2_1`, `testmods/2.1` or the legacy `testmods_2.1` layout, in that order. An external worktree should pass `-LocalModZipDir` explicitly when its sibling directory is not the canonical project storage root.

## Production boundary

This runbook does not authorize production keys, signatures, seals, tags, `main` or `legacy` promotion, GitHub release publication, Mod Portal upload, or cleanup. Those actions require a separate go/no-go over an exact frozen tree and exact candidate hashes.
