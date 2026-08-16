---
title: "MIR 3 Post-Terminal Emergency Hotfix"
status: current
applies_to: "3.2.10-and-conditional-2.5.10"
audience: release-manager
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-16
supersedes: []
superseded_by: []
---

# MIR 3 Post-Terminal Emergency Hotfix

This is an append-only exception to the MIR 3 terminal policy. The sealed and published `3.2.9` and `2.5.9` releases remain immutable historical releases. They must not be replaced, deleted, retagged, or repackaged.

The maintainer authorizes `3.2.10` for MIR3-TERM-0032 after reproduction, correction, deterministic construction, required upgrades, exact Factorio 2.1 qualification, sealing, and public-byte verification. `2.5.10` is pre-authorized but may be published only if exact Factorio 2.0.77 proof establishes the same defect or a genuinely package-visible shared correction.

The earlier no-`.10` rule remains historical authority. `MIR3PostTerminalEmergencyHotfixAuthorizationV1` supersedes it only for this maximum-level defect. MIR 4 R0 remains package-excluded and non-authoritative, public 4.x remains forbidden, and M4-003 behavioral qualification is paused until its terminal predecessor is settled.

## Maximum-level contract

- `0` means infinite progression.
- A positive integer `N` is the absolute highest technology level permitted.
- Completed levels above a newly lowered cap are retained and never silently unresearched.
- Current or queued research above the new cap is removed safely.
- Fractional progress is retained when its research remains valid.
- Raising a cap makes newly valid levels researchable again.
- Returning a cap to `0` restores infinite progression.
- First and second reloads must be idempotent.

On script-capable targets, MIR keeps managed technology prototypes infinite and publishes the effective compiler policy for runtime enforcement. This avoids Factorio clamping completed levels before configuration-change handlers run. The same policy covers generated streams, generated base continuations, native Space Age owners, direct startup values, and MIRSET1 imports. If another finalizer replaces the required infinite prototype with a finite maximum, MIR refuses to claim the runtime cap is active and logs the selected value, planned cap, observed cap, binding operation, setting, and conflict reason.

The controlling records are under `.mir/releases/emergency/`. Release gates, not elapsed time, decide publication.
