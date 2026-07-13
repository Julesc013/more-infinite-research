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
| Factorio 2.0 | 2.3.5 | `legacy` baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published predecessor | Exact 2.4 promotion pending |
| Factorio 2.0 | 2.4.0 | `tmp/2.0`, then `legacy` | live native-owner repair over `a853f88` safety point | Pending regeneration; prior `5E1D16CE...226E1` superseded | 82-scenario baseline retained; native-owner settings matrix must expand it | Reopened unreleased candidate | Implement, requalify, reseal, promote, then maintainer interactive/tag/release gates |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Wait for 2.4.0 tag and release |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Wait for 2.4.0 tag and release |

## Immediate Gate

Repair stream settings across generated, adopted, and already-covered native owners, then fully requalify MIR 2.4.0. The pre-repair 2.4 seal and older 2.4 and 2.5 evidence cannot qualify the changed package bytes. The internal 2.5 candidate remains identifiable by commit and digest only; release-facing identity and archive output remain 2.4.0.

## Next Executable Sequence

1. Implement and test the declarative native-owner configuration contract on `tmp/2.0`.
2. Rebuild once, run the expanded full Factorio 2.0 gate, and seal the exact archive.
3. Promote the exact sealed candidate to `legacy` without rebuilding and verify it there.
4. Push only the non-release branches, then stop for maintainer interactive review, tag, and publication.
5. Do not proceed to `tmp/1.1` or any older target in this run.
