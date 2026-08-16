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

This exact package was qualified locally and accepted by the maintainer on Steam Factorio `2.1.14` build `87180`. The release-specific emergency override replaces the former 2.1.13 gate for `3.2.10` only; it does not change the historical qualification claims of earlier releases.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.10.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `manually-accepted` |
| Candidate | `C34` |
| Package source commit | `19ddb7db4c960f77aef53d2bb47d23e0f311918f` |
| Archive SHA-256 | `5D88F2F971622E04846F6FC26859777F429C71FE34ECD9250AB2BA56B9A4C1B7` |
| Content SHA-256 | `B1F8CA3131D2161F2BA7D9181D060EB59C2D5F368D04546264A3150A01B915A9` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
