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
| Factorio 2.0 | 2.4.5 | `tmp/2.0` | Direct projection of `9c8f400` / canonical package source `79df29b` | `7649824B...D39F8` | Retained 94/94 behavior proof plus fresh exact-ZIP, upgrade, configuration-change, deterministic-build, and ecosystem checks on Factorio 2.0.77 | Qualified candidate awaiting immutable seal | Seal, promote exact commit to `legacy`, then maintainer review/tag/release |
| Factorio 2.0 | 2.5.0 internal candidate | safety identity `4f7c9d1` | preserved ledger | `0BE57ED4...CBFD` | 82-scenario historical evidence | Superseded; archive removed from release branch | None; not a release target |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | Existing qualified candidate | `431CD5B0...A46E` | Existing Factorio 1.1 proof retained | Paused and untouched | Outside the 2.4.5 hotfix run |
| Factorio 1.0 and older | Existing target branches | matching `tmp/*` | Existing records | Existing or pending | No work authorized in this gate | Paused | Outside the 2.4.5 hotfix run |

## Immediate Gate

Seal the exact 2.4.5 archive, push `tmp/2.0`, and promote the same committed tree to `legacy` without rebuilding.

## Next Executable Sequence

1. Verify the candidate seal from a clean source tree.
2. Push `tmp/2.0` and promote the exact commit to `legacy` without rebuilding.
3. Refresh the 3.1.9 `main` validation harness and sealed dist with the portable assurance fixes learned from 2.4.5.
4. Stop for maintainer interactive review, tags, and publication before beginning `tmp/1.1`.
