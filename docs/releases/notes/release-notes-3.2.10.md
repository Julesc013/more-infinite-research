---
title: "More Infinite Research 3.2.10 Release Notes"
status: current
applies_to: "3.2.10"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# More Infinite Research 3.2.10

3.2.10 is a narrow emergency hotfix for maximum research levels.

- Maximum level `0` remains infinite; a positive value is now enforced as the absolute highest permitted technology level.
- Lowering a cap no longer silently removes already completed levels.
- Invalid current and queued research above a lowered cap is removed safely.
- Raising or removing a cap restores future progression.
- The contract applies consistently to generated streams, generated base continuations, and all five Space Age native productivity owners.
- MIRSET1 imports use the same effective cap policy as direct startup settings.
- Late prototype overrides are reported instead of being misrepresented as an active cap.

The `3.2.9` release remains unchanged and downloadable.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.10.json`. The typed record is authoritative.

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
