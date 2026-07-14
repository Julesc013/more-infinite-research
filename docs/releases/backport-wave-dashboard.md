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
| Factorio 2.0 | 2.4.1 | `tmp/2.0` | published 2.4.0 plus `79df29b` regression | Pending | Focused disabled-Automation-science regression pending on Factorio 2.0 | Hotfix qualification in progress | Validate, package, seal, then stop for maintainer tag and release |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Outside the 2.4.1 hotfix run |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Outside the 2.4.1 hotfix run |

## Immediate Gate

Prove the reported disabled Automation science technology configuration on Factorio 2.0, qualify the exact 2.4.1 archive, seal it, push `tmp/2.0`, and stop before tagging or publication.

## Next Executable Sequence

1. Run the focused generated-prerequisite regression on Factorio 2.0.
2. Run static and impacted release validation once against the final source.
3. Build and inspect the deterministic 2.4.1 archive, then bind the candidate evidence and seal.
4. Push `tmp/2.0` and stop for maintainer interactive review, tag, and publication.
