---
title: "Backport Wave Dashboard"
status: current
applies_to: "3.1.5+"
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
| Factorio 2.1 | 3.1.5 | `main` | `3cd6a95` package source / `c8bf4a7` release | `8861E25F...7C50` | 91 scenarios, two exact upgrades, and 9 named ecosystem loads passed | Published canonical anchor | None for this backport |
| Factorio 2.0 | 2.3.5 | historical `legacy` baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published predecessor | None |
| Factorio 2.0 | 2.4.0 | `legacy` | `01efb39` package source / `584b398` release | `4BA19EA0...470C` | Change-aware qualification, exact-dist base/Space Age, and upgrade passed | Published | None |
| Factorio 2.0 | 2.4.1 | `tmp/2.0` | `f42b45d` package source plus `79df29b` regression | `7931E97D...AAC3D` | Focused regression and exact-dist base/Space Age loads passed on Factorio 2.0.77 | Runtime qualified; awaiting seal | Seal, push, then stop for maintainer tag and release |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Outside the 2.4.1 hotfix run |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Outside the 2.4.1 hotfix run |

## Immediate Gate

Seal the qualified 2.4.1 archive, push `tmp/2.0`, and stop before tagging or publication.

## Next Executable Sequence

1. Commit the qualification evidence and exact deterministic archive.
2. Seal and verify the candidate from a clean source tree.
3. Push `tmp/2.0` and stop for maintainer interactive review, tag, and publication.
