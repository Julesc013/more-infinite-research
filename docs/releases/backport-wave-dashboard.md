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
| Factorio 2.1 | 3.1.0 | `main` | `0dd8d7f` package source / `6272cb6` release | `0244D40A...7C1A` | 82 scenarios, exact upgrade, performance budgets, and interactive review passed | GitHub published and frozen | Mod Portal upload API key |
| Factorio 2.0 | 2.3.5 | `legacy` | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Tagged and frozen | External upload credentials |
| Factorio 2.0 | 2.4.0 | `tmp/2.0` | Accepted 3.1.0 anchor | Pending | Port and target-specific proof pending | Implementation authorized | Factorio 2.0 adaptation and validation |
| Factorio 1.1 | 1.9.4 planned | `tmp/1.1` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 1.0 | 1.8.2 planned | `tmp/1.0` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.18 | 1.8.0 | `tmp/0.18` | Published frozen evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Frozen verified | None |
| Factorio 0.17 | 1.7.1 planned | `tmp/0.17` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.16 | 1.6.0 planned | `tmp/0.16` | Pending proof | Pending | Binary available | Discovery | Old-science adapter proof |
| Factorio 0.15 | 1.5.0 planned | `tmp/0.15` | Pending proof | Pending | Binary available | Discovery | Independent native-infinite proof |
| Factorio 0.14 through 0.12 | Planned finite ladders | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Matching binary and schema proof |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Immediate Gate

MIR 3.1.0 and 2.3.5 are immutable anchors. Seed the 2.4.0 work only from the accepted 3.1.0 source and apply explicit positive Factorio 2.0 target cuts; do not merge target-local metadata back into `dev`.

## Next Executable Sequence

1. Create 2.4.0 on `tmp/2.0` from the accepted 3.1.0 source anchor and apply only positive Factorio 2.0 target cuts.
2. Re-run static, architecture, target-profile, fixture, exact-package, upgrade, performance, and interactive gates on Factorio 2.0.
3. Promote the independently accepted 2.4.0 archive without changing the frozen 2.3.5 or 3.1.0 bytes.
4. Replay the final portable patch set to older targets and run one full fixed-point sweep.
