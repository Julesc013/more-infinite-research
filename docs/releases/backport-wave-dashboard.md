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
| Factorio 2.1 | 3.1.9 | `main` | `79df29b` package source / `9c8f400` release candidate | `D77B3A78...DFCD` | Exact seal and 102-scenario qualification verified | Sealed canonical anchor awaiting maintainer tag | Maintainer review, tag, and release |
| Factorio 2.0 | 2.3.5 | historical `legacy` baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published predecessor | None |
| Factorio 2.0 | 2.4.0 | `legacy` | `01efb39` package source / `584b398` release | `4BA19EA0...470C` | Change-aware qualification, exact-dist base/Space Age, and upgrade passed | Published | None |
| Factorio 2.0 | 2.4.1 | `tmp/2.0` | Direct projection of `9c8f400` / canonical package source `79df29b` | Pending replacement candidate | Changed-feature checks plus one complete Factorio 2.0.77 qualification required | Reconstruction in progress; old six-scenario candidate superseded | Complete qualification and seal, then maintainer review/tag/release |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Outside the 2.4.1 hotfix run |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Outside the 2.4.1 hotfix run |

## Immediate Gate

Push the sealed 2.4.1 archive on `tmp/2.0` and stop before tagging or publication.

## Next Executable Sequence

1. Verify the candidate seal from a clean source tree.
2. Push `tmp/2.0` and stop for maintainer interactive review, tag, and publication.
