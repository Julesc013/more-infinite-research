---
title: "More Infinite Research 3.2.11 Release Notes"
status: current
applies_to: "3.2.11"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-17
supersedes: []
superseded_by: []
---

# More Infinite Research 3.2.11

3.2.11 corrects how finite maximum research levels are presented while retaining the lossless cap enforcement introduced in 3.2.10.

- A positive maximum now hides Factorio's internal infinity badge and states the exact configured maximum in the technology description.
- Maximum `0` retains the normal infinite presentation.
- Research above a finite maximum cannot be started or queued, while completed levels above a newly lowered cap remain intact.
- Raising a cap or returning it to `0` restores future progression.
- Generated item and fluid streams, base continuations, direct-effect streams, and Space Age native productivity owners use the same contract.
- A skipped base-continuation replacement no longer removes another mod's technology or rewires its dependants.

MIR 3.2.10 remains unchanged and downloadable as the immutable predecessor.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.11.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `sealed` |
| Candidate | `C35` |
| Package source commit | `0a32864d1f1d1fdea090369bc1a22fbd511e290a` |
| Archive SHA-256 | `5B0252C3E1B8A20FF8E31F408F0217DDC77D2DF0D1C15F59653E948472870A5A` |
| Content SHA-256 | `FFF55368B65766D29049DF8E4DC845B38A6D4A65F1512EE62D277AD796181F89` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
