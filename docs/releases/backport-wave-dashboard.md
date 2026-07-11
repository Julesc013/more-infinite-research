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
| Factorio 2.1 | 3.0.5 | `main` | `b93808c` package source / `89d7764` release | `40AF95C3...E5C5` | 79 scenarios and manual acceptance passed | Published and frozen | None |
| Factorio 2.0 | 2.3.5 | `tmp/2.0` | `861565d` / evidence `7588ead` | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Candidate qualified | Interactive settings UI review |
| Factorio 1.1 | 1.9.4 planned | `tmp/1.1` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 1.0 | 1.8.2 planned | `tmp/1.0` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.18 | 1.8.0 | `tmp/0.18` | Published frozen evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Frozen verified | None |
| Factorio 0.17 | 1.7.1 planned | `tmp/0.17` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.16 | 1.6.0 planned | `tmp/0.16` | Pending proof | Pending | Binary available | Discovery | Old-science adapter proof |
| Factorio 0.15 | 1.5.0 planned | `tmp/0.15` | Pending proof | Pending | Binary available | Discovery | Independent native-infinite proof |
| Factorio 0.14 through 0.12 | Planned finite ladders | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Matching binary and schema proof |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Immediate Gate

MIR 2.3.5 must not be tagged or published until the exact archive is inspected in the Factorio 2.0 startup settings UI and retained values are accepted. The archive is frozen; the review must not rebuild it.

## Next Executable Sequence

1. Complete the 2.3.5 interactive review, promote the exact candidate to `legacy`, publish, and freeze it.
2. Create the `pre-3.1-modernization` annotated baseline from released 3.0.5 plus accepted portable-return records.
3. Implement the bounded 3.1 work in dependency order: characterization, facts/indexes, pure contracts, mutation commands, fixtures, validation decomposition, deterministic packaging, performance evidence, then feature slice.
4. Release 3.1 only after its independent gates pass.
5. Create 2.4.0 from the accepted 3.1 source anchor and apply only positive Factorio 2.0 target cuts.
6. Replay the final portable patch set to older targets and run one full fixed-point sweep.
