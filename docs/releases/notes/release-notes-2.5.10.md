---
title: "More Infinite Research 2.5.10 Release Notes"
status: current
applies_to: "2.5.10"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# More Infinite Research 2.5.10

This emergency hotfix brings the 3.2.10 lossless absolute maximum-level contract to Factorio 2.0.77. It fixes the configured caps for processing units, plastic bars, low-density structures, rocket fuel, and steel plates on MIR's generated-technology path.

Positive values are absolute highest permitted research levels; zero remains infinite. Lowering a cap retains completed levels, safely removes invalid current and queued research, and raising or removing the cap restores future progression. Direct startup settings, MIRSET1 imports, and configuration changes were exercised on the exact Factorio 2.0.77 executable. MIR 2.5.9 remains unchanged and downloadable.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/2.5.10.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `sealed-awaiting-publication` |
| Candidate | `2.5-P14` |
| Package source commit | `pending` |
| Archive SHA-256 | `251EFDAB4983CDFF0E2C150304DF7B7846EDEA6E1B5B0927C3FBBD8449E65DAB` |
| Content SHA-256 | `55908E821FB48F244C9A81560F81BBFDF6CD274195D38F1A2811E652588D5D66` |
| Tag | `2.5.10` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
