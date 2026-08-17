---
title: "More Infinite Research 2.5.11 Release Notes"
status: current
applies_to: "2.5.11"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-18
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
- Skipping a capped base-continuation replacement leaves another mod's owner and dependent prerequisites unchanged.

MIR 2.5.10 remains unchanged and downloadable as the immutable predecessor.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/2.5.11.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `package-built` |
| Candidate | `2.5-P15` |
| Package source commit | `57324642e7423d784d7f22b9be4a2b6b350bf012` |
| Archive SHA-256 | `4AE3DA83C4F8CB7D084891065387B78032BB25B8E4ED3948058D9B773070847C` |
| Content SHA-256 | `F8964470F580810C2113750A1A5F10CCA8084D7CE0F42108BECC993D7076D32D` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `none authorized` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
