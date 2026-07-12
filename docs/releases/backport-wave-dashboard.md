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
| Factorio 2.0 | 2.4.0 | `tmp/2.0` | `b9172ab` source / `575fc4f` release | `8618CAF0...A12` | 78 scenarios, exact-dist base/Space Age, upgrade, performance, and interactive review passed | GitHub published and frozen | Mod Portal upload API key |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | `4f3962f` qualified candidate | `431CD5B0...A46E` | Factorio 1.1.110 reduced full gate, exact dist, reload, and upgrade passed | Candidate qualified | Publication gate |
| Factorio 1.0 | 1.8.2 staged | `tmp/1.0` | `aeb1483` staged candidate | `4ED750E5...0D3C` | Static package staging only; prior exact-save automation did not load MIR | Unqualified | Correct Factorio 1.0 runtime proof |
| Factorio 0.18 | 1.8.0 | `tmp/0.18` | Published frozen evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Frozen verified | None |
| Factorio 0.17 | 1.7.1 planned | `tmp/0.17` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.16 | 1.6.0 planned | `tmp/0.16` | Pending proof | Pending | Binary available | Discovery | Old-science adapter proof |
| Factorio 0.15 | 1.5.0 planned | `tmp/0.15` | Pending proof | Pending | Binary available | Discovery | Independent native-infinite proof |
| Factorio 0.14 through 0.12 | Planned finite ladders | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Matching binary and schema proof |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Immediate Gate

MIR 3.1.0, 2.3.5, and 2.4.0 are immutable anchors. Continue the plan-first automatic family compiler on `dev` from the released 3.1.0 behavior baseline. Do not merge Factorio 2.0 metadata or feature cuts upward.

## Next Executable Sequence

1. Compile all fixed streams through a pure whole-plan validation gate without changing their stable IDs.
2. Consolidate recipe facts and indexes, then enable fixture-backed attach-only family rules.
3. Keep ambiguous candidates diagnostic-only and prove decisions with golden plans and target runtime scenarios.
4. Finish the independently qualified old-target candidates without changing any published archive bytes.
