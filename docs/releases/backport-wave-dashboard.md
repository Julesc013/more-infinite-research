---
title: "Backport Wave Dashboard"
status: current
applies_to: "3.1.9+"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# Backport Wave Dashboard

`.mir/release-wave.yml` is the machine-readable status authority. A target is complete only when its evidence supports its stated release state.

| Target | MIR version | Branch | Source | Archive SHA-256 | Binary state | Status | Blocker |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Factorio 2.1 | 3.1.9 | `main` | `79df29b` package source / `f81af94` seal source | `D77B3A78...DFCD` | 102-scenario composite plus fresh progress, exact-ZIP, upgrade, and exact BZ canary; final seal verified | Sealed candidate on `main` awaiting maintainer tag | Maintainer review, tag, and release |
| Factorio 2.0 | 2.3.5 | historical `legacy` baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published predecessor | None |
| Factorio 2.0 | 2.4.0 | `legacy` | `01efb39` package source / `584b398` release | `4BA19EA0...470C` | Change-aware qualification, exact-dist base/Space Age, and upgrade passed | Published | None |
| Factorio 2.0 | 2.4.5 | `tmp/2.0` / `legacy` | Direct projection of `9c8f400` / canonical package source `79df29b` | `7649824B...D39F8` | Retained 94/94 behavior proof plus fresh exact-ZIP, upgrade, configuration-change, deterministic-build, ecosystem, and seal checks on Factorio 2.0.77 | Exact sealed tree pushed to both branches | Maintainer review, tag, and release |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Outside the 2.4.5 hotfix run |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Outside the 2.4.5 hotfix run |

## Immediate Gate

MIR 2.4.5 and 3.1.9 are sealed on `legacy` and `main` respectively. Stop for maintainer review, tags, and publication.

## Next Executable Sequence

1. Maintainer tests, tags, and publishes MIR 2.4.5 from `legacy`.
2. Maintainer tests, tags, and publishes MIR 3.1.9 from `main`.
3. Only after both release pauses close, return the portable harness lessons through `dev` and begin the 1.9.4 work on `tmp/1.1`.
