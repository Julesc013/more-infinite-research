---
title: "MIR 3.2.9 Release Notes"
status: current
applies_to: "3.2.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-15
supersedes: []
superseded_by: []
---

# More Infinite Research 3.2.9

Final MIR 3 terminal release for Factorio 2.1.13.

Candidate: `C33`

Archive SHA-256: `0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20`

Normalized content SHA-256: `FE68D37CCDB0685120579AF04AA62ABA7DD41F1F4AF01A02B72015A907794B25`

Upgrade paths: `3.2.5 -> 3.2.9` and `3.2.3 -> 3.2.9`

## Changes

- Corrects K2/K2SO science-card phasing for the qualified K2 2.1.2 and K2SO 2.0.13 envelope.
- Selects the deterministic earliest safe science-production route instead of an arbitrary technology-name gate.
- Resolves direct-effect ownership across the combined compilation plan, including the reported Tesla shooting-speed startup crash.
- Preserves stable technology IDs, completed research, current research, fractional progress, queue state, and reload behavior across the governed upgrades.
- Keeps every released setting in its existing Startup/compile scope; MIRSET1 and setting identities are unchanged.
- Establishes the permanent MIR 3 Factorio 2.1 baseline. Future architecture work belongs to MIR 4.

## Qualification

The exact archive was reconstructed three times from clean detached roots and passed its target-tier automated qualification. Maintainer acceptance is limited to inspection of the exact frozen distribution; engine, settings, compatibility, performance, and upgrade claims come from the recorded automated evidence.

## Installation

Use the attached `more-infinite-research_3.2.9.zip` unchanged. Do not rename or unpack it into another archive.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.9.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `publicly-verified` |
| Candidate | `C33` |
| Package source commit | `255a20df771ae5fa3a38007bd2268bab3e9e1eff` |
| Archive SHA-256 | `0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20` |
| Content SHA-256 | `FE68D37CCDB0685120579AF04AA62ABA7DD41F1F4AF01A02B72015A907794B25` |
| Tag | `3.2.9` |
| Tag commit | `a60230a0695d2dd8fd1e727744614e746cda0bd8` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
