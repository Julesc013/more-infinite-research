---
title: "More Infinite Research 2.5.11 Release Notes"
status: current
applies_to: "2.5.11"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# More Infinite Research 2.5.11

2.5.11 brings the corrected finite maximum-level presentation and enforcement contract to Factorio 2.0.77.

- A positive maximum states the exact configured cap instead of showing a misleading infinity badge.
- Maximum `0` retains normal infinite progression and presentation.
- Research above the selected cap cannot be started or queued, while completed levels survive a newly lowered cap.
- Raising or removing the cap restores valid future research.
- Generated productivity streams and base continuations follow the same rule.
- Skipping a capped base-continuation replacement leaves another mod's owner and dependant prerequisites unchanged.

MIR 2.5.10 remains unchanged and downloadable as the immutable predecessor.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/2.5.11.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `planned` |
| Candidate | `not-assigned` |
| Package source commit | `pending` |
| Archive SHA-256 | `pending` |
| Content SHA-256 | `pending` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
