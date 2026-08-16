---
title: "Releases"
status: current
applies_to: "MIR 3 terminal release train"
audience: release-manager
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: []
---

# Releases

The MIR 3 `.5` wave is published and immutable. The single active planning authority is the [MIR 3 terminal `.9` programme](mir-3-terminal-dot-9-programme.md). It routes every later MIR 3 correction to the matching `.9` line, prohibits `.6` through `.8`, and hands the completed programme to MIR 4.

Machine-readable release authority lives in `.mir/releases/records/`, with current roles in `.mir/releases/records/current.json` and the wave decision in `.mir/releases/waves/MIR3-Terminal-ChangeSet.json`. Generated dashboards and `todo.md` are views, not independent release state.

## Current published wave

| Factorio target | Published release | Next planned release | State |
| --- | --- | --- | --- |
| `2.1` | [`3.2.5`](notes/release-notes-3.2.5.md) | [`3.2.9`](notes/release-notes-3.2.9.md) | Publicly verified; protected qualification and seal reconciliation remain post-publication debt |
| `2.0` | [`2.5.5`](notes/release-notes-2.5.5.md) | `2.5.9` | Publicly verified; protected qualification and seal reconciliation remain post-publication debt |
| `1.1.110` | [`1.9.5`](notes/release-notes-1.9.5.md) | `1.9.9` | Publicly verified |
| `1.0.0` only | [`1.8.5`](notes/release-notes-1.8.5.md) | `1.8.9` | Publicly verified; no Factorio 0.18 claim |
| `0.17.79` | [`1.7.5`](notes/release-notes-1.7.5.md) | `1.7.9` | Publicly verified |
| `0.16.51` | [`1.6.5`](notes/release-notes-1.6.5.md) | `1.6.9` | Publicly verified |
| `0.15.40` | [`1.5.5`](notes/release-notes-1.5.5.md) | `1.5.9` | Publicly verified |
| `0.14.23` | [`1.4.5`](notes/release-notes-1.4.5.md) | `1.4.9` | Publicly verified |
| `0.13.20` | [`1.3.5`](notes/release-notes-1.3.5.md) | `1.3.9` | Publicly verified |

The `.5` publication exceptions remain release-specific. They do not claim normal protected qualification, do not create protected seals, and do not weaken the normal `.9` gates.

## Current release documents

- [MIR 3 terminal `.9` programme](mir-3-terminal-dot-9-programme.md)
- [Backport wave dashboard](backport-wave-dashboard.md)
- [Target-line versioning and backports](../maintainer/backporting.md)
- [Current Mod Portal page](mod-portal-page.md)
- [Release-note index](notes/README.md)
- [MIR 4 offline release authority](../architecture/mir4-offline-release-authority.md)

## Historical records

Completed plans, candidate reports, publication receipts, previous Mod Portal copy, and superseded roadmaps live under [`docs/releases/archive/`](archive/). Archived pages are evidence and context only; their replacement is this index or the current page named in their frontmatter.
