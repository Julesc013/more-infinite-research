---
title: "Releases"
status: current
applies_to: "MIR 3 terminal release train and MIR 4.0 candidate programme"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-18
supersedes: []
superseded_by: []
---

# Releases

The MIR 3 terminal `.9` family is sealed, GitHub-published, and verified. The [MIR 3 terminal `.9` programme](mir-3-terminal-dot-9-programme.md) remains the custody authority while Mod Portal upload/redownload evidence and EOL closure are completed. It routes every later MIR 3 correction to the matching `.9` line, prohibits `.6` through `.8`, and hands the completed programme to MIR 4.

Machine-readable release authority lives in `.mir/releases/records/`, with current roles in `.mir/releases/records/current.json` and the wave decision in `.mir/releases/waves/MIR3-Terminal-ChangeSet.json`. Generated dashboards and `todo.md` are views, not independent release state.

## Current terminal wave

| Factorio target | Terminal release | GitHub custody | Mod Portal custody |
| --- | --- | --- | --- |
| `2.1` | [`3.2.9`](notes/release-notes-3.2.9.md) | Published and redownload-verified | Visible; authenticated redownload still required for EOL |
| `2.0` | [`2.5.9`](notes/release-notes-2.5.9.md) | Published and redownload-verified | Visible; authenticated redownload still required for EOL |
| `1.1.110` | [`1.9.9`](notes/release-notes-1.9.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |
| `1.0.0` only | [`1.8.9`](notes/release-notes-1.8.9.md) | Published and redownload-verified | Upload and authenticated redownload pending; no Factorio 0.18 claim |
| `0.17.79` | [`1.7.9`](notes/release-notes-1.7.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |
| `0.16.51` | [`1.6.9`](notes/release-notes-1.6.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |
| `0.15.40` | [`1.5.9`](notes/release-notes-1.5.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |
| `0.14.23` | [`1.4.9`](notes/release-notes-1.4.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |
| `0.13.20` | [`1.3.9`](notes/release-notes-1.3.9.md) | Published and redownload-verified | Upload and authenticated redownload pending |

The historical `.5` publication exceptions remain release-specific. They do not weaken the terminal `.9` gates or authorize MIR 4 publication. The live R0 dashboard is authoritative for the remaining custody and EOL blockers.

## Current release documents

- [MIR 3 terminal `.9` programme](mir-3-terminal-dot-9-programme.md)
- [Backport wave dashboard](backport-wave-dashboard.md)
- [Target-line versioning and backports](../maintainer/backporting.md)
- [Current Mod Portal page](mod-portal-page.md)
- [Release-note index](notes/README.md)
- [MIR 4 offline release authority](../architecture/mir4-offline-release-authority.md)
- [MIR 4.0 candidate programme](mir4-4.0-candidate-programme.md)
- [MIR 4.0 prepared publication copy and FAQ](mir4-4.0-publication-copy.md)
- [Superseded MIR 4 bootstrap local beta plan](mir4-bootstrap-local-beta-plan.md)

## Historical records

Completed plans, candidate reports, publication receipts, previous Mod Portal copy, and superseded roadmaps live under [`docs/releases/archive/`](archive/). Archived pages are evidence and context only; their replacement is this index or the current page named in their frontmatter.
