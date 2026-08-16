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

## Maintainer release override — 2026-08-16

The maintainer accepted the exact C34 ZIP after a manual playtest on the installed Steam Factorio `2.1.14` build `87180`. Local automated qualification on that same version covered the 13 maximum-level scenarios, all three governed upgrade origins, the retained K2/route/Tesla/Space Exploration checks, and deterministic A/B/C reconstruction. The release-specific override waives the superseded exact-2.1.13 and separately staged protected/seal ceremony for `3.2.10`; it does not claim those gates passed and does not alter generic release policy.

The accepted ZIP is `dist/more-infinite-research_3.2.10.zip`, SHA-256 `5D88F2F971622E04846F6FC26859777F429C71FE34ECD9250AB2BA56B9A4C1B7`, normalized content SHA-256 `B1F8CA3131D2161F2BA7D9181D060EB59C2D5F368D04546264A3150A01B915A9`, 1,065,178 bytes, and 304 entries. Those bytes are frozen for tag and GitHub publication.

After publication, the movable `legacy` branch becomes an exact alias of the `3.2.10` release commit. This changes the branch role only: immutable `2.5.9` and `3.2.9` tags, releases, and assets remain available and unchanged. `2.5.10` is not published, and no Factorio 2.0 applicability claim is made.

The machine authority is `MIR3PostTerminalEmergencyHotfixMaintainerReleaseOverrideV1`. Repository cleanup remains a read-only audit; no deletion is part of this override.

## Publication — 2026-08-16

`3.2.10` was merged to protected `main` at `4cbea531a1043e0cacb9ac5c496731c8d77bbdb6`, annotated with immutable tag `3.2.10`, and published as the GitHub Latest release. A fresh public redownload reproduced SHA-256 `5D88F2F971622E04846F6FC26859777F429C71FE34ECD9250AB2BA56B9A4C1B7` and 1,065,178 bytes exactly. The append-only publication receipt is `.mir/evidence/terminal-publication/2026-08-16/github/3.2.10.json`.

The immutable tag message contains two incorrect descriptive package-source fields. The tag itself points to the correct protected-main release commit and records the correct release tree, archive hash, content hash, engine identity, and promotion proof. The authoritative package source remains commit `19ddb7db4c960f77aef53d2bb47d23e0f311918f`, tree `46eb4cd0c48a1d997a632a3ff83606d19d9af19a`; the receipt records the correction without rewriting the tag.

Post-publication qualification passed static validation and 14 consecutive Factorio 2.1.14 runtime rows before `base-competitor-rollback` reproduced MIR3-TERM-0033: when an absolute cap is below the first generated base-extension level, the external owner is removed before MIR skips replacement. The public ZIP is unchanged. Under the maintainer's direction that remaining issues move to MIR 4, the exact observation is retained at `.mir/evidence/terminal-publication/2026-08-16/runtime/3.2.10-base-competitor-rollback.json` and is a required M4-003 follow-up.
