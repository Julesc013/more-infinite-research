---
title: "Backport Wave Dashboard"
status: current
applies_to: "3.0.5+"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# Backport Wave Dashboard

`.mir/release-wave.yml` is the machine-readable status authority. A target is complete only when its evidence supports its stated release state.

| Target | MIR version | Branch | Source | Archive SHA-256 | Binary state | Status | Blocker |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Factorio 2.1 | 3.1.1 | `main` published baseline | `e91963c` | `FAAA6AA3...C7EB9` | Published emergency Galore ownership hotfix | Published and frozen | None |
| Factorio 2.1 | 3.1.2 | `main` | `b36996a` source / `4d74514` evidence | `D5BFA665...25F5` | 91 scenarios, exact upgrade, ecosystem 9/9, and exact dist passed | Candidate qualified | Manual release decision |
| Factorio 2.1 | 3.1.5 | `dev` | `d8a6483` qualified source | `456550A8...F1F6` | 91 scenarios, exact 3.0.5 upgrade, ecosystem 9/9, and exact dist passed | Candidate qualified | Manual release decision |
| Factorio 2.0 | 2.3.5 | `legacy` published baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published and frozen | None |
| Factorio 2.0 | 2.5.0 | `tmp/2.0` | `f5c58f5` qualified source | `0BE57ED4...CBFD` | Factorio 2.0.77 full 82-scenario gate and exact dist passed | Candidate qualified | Publication gate; 2.4.0 bytes remain immutable |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | `30ef8c7` qualified source | `9184524A...A35` | Factorio 1.1.110 10 scenarios, exact fresh/reload, and 1.9.3 upgrade passed | Candidate qualified | Publication gate |
| Factorio 1.0 | 1.8.2 | `tmp/1.0` | `0b06b9b` qualified source | `1D474CF4...EDF6` | Factorio 1.0.0 10 scenarios, exact fresh/reload, and genuine 1.8.1 upgrade passed | Candidate qualified | Publication gate |
| Factorio 0.18 | 1.8.0 bridge | `tmp/0.18` | Historical bridge evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Evidence only | 1.8.2 Factorio 1.0 qualification |
| Factorio 0.17 | 1.7.1 | `tmp/0.17` | `efb5d0a` qualified source | `CC112180...1BFA` | Factorio 0.17.79 9 scenarios, exact fresh/reload, and 1.7.0 upgrade passed | Candidate qualified | Publication gate |
| Factorio 0.16 | 1.6.0 | `tmp/0.16` | `2dfb1a7` qualified source | `6EE5FF57...6BAB` | Factorio 0.16.51 8 scenarios, exact package/fresh, and server reload passed | Candidate qualified | Publication gate |
| Factorio 0.15 | 1.5.0 | `tmp/0.15` | `d416787` qualified source | `2EB2E965...817` | Factorio 0.15.40 4 target scenarios, exact package/fresh, and server reload passed | Candidate qualified | Publication gate |
| Factorio 0.14 | 1.4.0 | `tmp/0.14` | `fa3b532` qualified source | `F6E90F29...CBD6` | Factorio 0.14.23 2 target scenarios, exact package/fresh, and server reload passed | Candidate qualified | Publication gate |
| Factorio 0.13 | 1.3.0 | `tmp/0.13` | `095264d` qualified source | `3061783F...80AF` | Factorio 0.13.20 2 target scenarios, exact package/fresh, and server reload passed | Candidate qualified | Publication gate |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Completed Wave

The 3.1.2 technology-cycle hotfix and every requested descending target are candidate-qualified and pushed without tags or releases. MIR 2.5.0 is used for Factorio 2.0 because the earlier 2.4.0 archive is immutable. Target metadata, finite-research emulation, old science names, effect whitelists, and engine-specific runtime cuts remain isolated on their target branches.

## Next Executable Sequence

1. Finish the portable return sweep as untagged MIR 3.1.5 on `dev`.
2. Run the complete Factorio 2.1 matrix, exact upgrade, ecosystem checks, and exact-dist qualification.
3. Keep `main` on the exact 3.1.2 candidate until a human chooses which candidate to tag and publish.
4. Tag or release only in a separate explicitly authorized publication turn.
