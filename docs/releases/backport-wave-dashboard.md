---
title: "Backport Wave Dashboard"
status: current
applies_to: "3.0.5+"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Backport Wave Dashboard

`.mir/release-wave.yml` is the machine-readable status authority. A target is complete only when its evidence supports its stated release state.

| Target | MIR version | Branch | Source | Archive SHA-256 | Binary state | Status | Blocker |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Factorio 2.1 | 3.1.0 | `main` / `dev` | `0dd8d7f` package source / `6272cb6` release | `0244D40A...C1A` | 82 scenarios and interactive acceptance passed | Published and frozen | Mod Portal upload key |
| Factorio 2.0 | 2.4.0 | `tmp/2.0` | `b9172ab` package source / `575fc4f` release | `8618CAF0...A12` | 78 scenarios, targeted gate, exact-dist, upgrade, and interactive review passed | Published and frozen | Mod Portal upload key |
| Factorio 2.0 baseline | 2.3.5 | `legacy` | `861565d` / evidence `7588ead` | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Tagged and frozen | External upload credential |
| Factorio 1.1 | 1.9.4 planned | `tmp/1.1` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 1.0 | 1.8.2 planned | `tmp/1.0` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.18 | 1.8.0 | `tmp/0.18` | Published frozen evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Frozen verified | None |
| Factorio 0.17 | 1.7.1 planned | `tmp/0.17` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.16 | 1.6.0 planned | `tmp/0.16` | Pending proof | Pending | Binary available | Discovery | Old-science adapter proof |
| Factorio 0.15 | 1.5.0 planned | `tmp/0.15` | Pending proof | Pending | Binary available | Discovery | Independent native-infinite proof |
| Factorio 0.14 through 0.12 | Planned finite ladders | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Matching binary and schema proof |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Immediate Gate

The requested modern release trio is complete: 3.1.0 remains frozen on the modern line, 2.3.5 remains the immutable `legacy` baseline, and 2.4.0 is frozen on `tmp/2.0`. Older target work remains independently gated by positive target profiles, matching binaries, and the fixed-point rule.

## Next Executable Sequence

1. Preserve the published 3.1.0 and 2.4.0 archives and the tagged 2.3.5 baseline without rebuilding them.
2. Queue the reusable 2.4.0 fixture and validation lessons for the next modern development release without returning target-local metadata or feature cuts.
3. Replay the final portable patch set to older targets in descending order only where matching binaries and target declarations exist.
4. Run one full fixed-point sweep and close the broader historical wave only if it yields no new portable fixes.
