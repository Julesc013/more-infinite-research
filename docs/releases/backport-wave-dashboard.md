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
| Factorio 2.1 | 3.0.5 | `main` published baseline | `89d7764` | `40AF95C3...0E5C5` | Published characterization and runtime gates passed | Published and frozen | None |
| Factorio 2.1 | 3.1.1 | `dev` | Pending hotfix acceptance | Pending | Galore-shaped regression and compiler contracts pass; full 90-scenario and release evidence are rebuilding | Hotfix validation | Full gate and exact archive qualification |
| Factorio 2.0 | 2.3.5 | `legacy` published baseline | `861565d` source / `9eabc54` promotion | `97B3DC9B...68DE` | 71 scenarios, targeted gate, exact-dist base/Space Age, and upgrade passed | Published and frozen | None |
| Factorio 2.0 | 2.4.0 | `tmp/2.0` | Must be re-derived from accepted 3.1.1 | Pending | Preserved pre-acceptance work is non-authoritative | Blocked | Accepted 3.1.1 source |
| Factorio 1.1 | 1.9.4 | `tmp/1.1` | `4f3962f` qualified candidate | `431CD5B0...A46E` | Factorio 1.1.110 reduced full gate, exact dist, reload, and upgrade passed | Candidate qualified | Publication gate |
| Factorio 1.0 | 1.8.2 staged | `tmp/1.0` | `aeb1483` staged candidate | `4ED750E5...0D3C` | Static package staging only; prior exact-save automation did not load MIR | Unqualified | Correct Factorio 1.0 runtime proof |
| Factorio 0.18 | 1.8.0 bridge | `tmp/0.18` | Historical bridge evidence | `D785E6EB...7B24` | 0.18 and 1.0 bridge passed | Evidence only | 1.8.2 Factorio 1.0 qualification |
| Factorio 0.17 | 1.7.1 planned | `tmp/0.17` | Pending replay | Pending | Binary available | Refresh pending | Final portable patch set |
| Factorio 0.16 | 1.6.0 planned | `tmp/0.16` | Pending proof | Pending | Binary available | Discovery | Old-science adapter proof |
| Factorio 0.15 | 1.5.0 planned | `tmp/0.15` | Pending proof | Pending | Binary available | Discovery | Independent native-infinite proof |
| Factorio 0.14 | 1.4.0 planned | `tmp/0.14` | Pending proof | Pending | Binary available | Discovery | Target-era schema and finite/native proof |
| Factorio 0.13 | 1.3.0 planned | `tmp/0.13` | Pending proof | Pending | Binary available | Discovery | Target-era schema and finite/native proof |
| Factorio 0.11 through 0.6 | Museum versions | matching `tmp/*` | Pending | Pending | Unresolved | Discovery | Binary and base-file acquisition |

## Immediate Gate

MIR 3.0.5 and 2.3.5 are the immutable published anchors. Complete and release the deterministic effect-ownership hotfix as MIR 3.1.1 on `dev`. Do not merge Factorio 2.0 metadata or feature cuts upward, and do not open 3.2.0 until the full stability ladder returns its portable lessons.

## Next Executable Sequence

1. Freeze one clean 3.1.1 hotfix candidate, rerun the full matrix, exact upgrade, available ecosystems, and exact-dist checks invalidated by the source change.
2. Complete the exact-archive GUI review, publish the exact tested bytes, and mark them immutable without overstating unavailable Angel, Space Exploration, or Pyanodon campaigns.
3. Create MIR 2.4.0 on the Factorio 2.0 line from accepted modern source with target-declared cuts only.
4. Qualify 1.9.4, 1.8.2, 1.7.1, 1.6.0, 1.5.0, 1.4.0, and 1.3.0 in descending order with matching binaries.
5. Classify and return portable lessons after each target, close the fixed-point sweep into `dev`, then open MIR 3.2.0.
