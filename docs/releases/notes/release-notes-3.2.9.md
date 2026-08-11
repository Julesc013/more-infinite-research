---
title: "MIR 3.2.9 Planning Notes"
status: draft
applies_to: "3.2.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-08
supersedes: []
superseded_by: []
---

# MIR 3.2.9 Planning Notes

MIR 3.2.9 is the planned final MIR 3 release for Factorio 2.1. These are planning notes, not released changes or a compatibility claim.

The release starts from immutable MIR 3.2.5 and is limited to admitted defect corrections, stabilization, documentation and locale corrections, package and migration corrections, performance corrections, and release-assurance hardening. MIR 3.2.5 remains the current public release until an exact 3.2.9 candidate completes the normal release gate.

There will be no MIR 3.2.6, 3.2.7, or 3.2.8 releases. The detailed cross-target policy is the [MIR 3 terminal `.9` programme](../mir-3-terminal-dot-9-programme.md).

## Current implementation state

The admitted implementation now contains `SciencePackProductionRoutePolicyV1`, which evaluates alternate recipes as independent production routes and selects the deterministic earliest safe route before technology names can break a tie. A Factorio 2.1 fixture proves that adding a lexically earlier but downstream route does not delay an already-reachable science pack.

The implementation also contains exact-version-gated `K2SciencePhasePolicyV1` for Krastorio 2 `2.1.2` with K2SO `2.0.13`. The policy normalizes only MIR-owned stream and base-continuation technologies after lab-compatible science selection, preserves technology IDs and ingredient shapes, and does nothing when the exact envelope is absent. Focused fixture proof is complete; exact K2SO campaign and direct-upgrade proof remain required before this becomes a release claim.

Direct unmodified Cubium 1.0.28 proof on Factorio 2.0 remains pending authenticated archive acquisition. No unmodified Cubium 2.1 support claim is made while that upstream release cannot load on Factorio 2.1 without a diagnostic shim.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `path:releases.records/3.2.9.json`. The typed record is authoritative.

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
