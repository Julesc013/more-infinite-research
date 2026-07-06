---
title: "More Infinite Research 2.1.5 Release Notes"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 2.1.5 Release Notes

This is the short, player-facing release summary for the `2.1.5` GitHub and Mod Portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Summary

`2.1.5` is a compatibility and release-hardening patch for the Factorio `2.1` line. It keeps gameplay behavior conservative while improving duplicate-productivity cooperation, audit diagnostics, local release gates, and maintainer tooling.

This release does **not** add broad new productivity systems. It focuses on safe compatibility fixes, exact duplicate avoidance, and better evidence when MIR chooses to generate, skip, or leave another mod's technology alone.

## Compatibility

- Added guarded known-competitor profiles for exact infinite recipe-productivity overlaps found in the July 2026 local idea-mod audit.
- MIR now skips its own lab productivity stream when a matching infinite native `laboratory-productivity` owner is active.
- MIR now skips its own worker robot battery stream when a Better Bot Battery-style infinite native worker robot battery owner is active.
- Finite lead-in technologies from other mods are preserved; the skip/cleanup logic targets only the narrow infinite-owner cases MIR can prove.
- Added diagnostics-only compatibility planner rows so logs and audit reports can explain active mod roles, planned non-actions, and known audit signals.
- Added recipe productivity cap diagnostics for recipes with non-default `maximum_productivity` values.

## Diagnostics

- Compatibility audits now write `compat-observations.md`, `compat-observations.json`, and `compat-observations.csv` for planner and recipe-cap diagnostics.
- Added `mir.ps1 report observations --run <path>` to summarize compatibility observation rows.
- Overnight and HTML reports now surface compatibility observation artifacts alongside grouped failures, missing dependencies, and profile candidates.
- The deterministic `AuditSmoke` gate now performs the baseline load check and captures MIR audit rows instead of acting as metadata-only coverage.

## Tooling

- Fixed local audits so official built-ins include required official dependencies such as Recycler for Quality.
- Fixed offline dependency closure for Factorio `~` dependencies such as Mini Machines' shared settings mod.
- Kept generated local scenarios rooted in configured root zips instead of dependency-only library zips.
- Allowed generated and baseline local audit scenarios with no root mods.
- Shortened audit user-data paths to avoid Windows path-length false negatives.
- Added optional hardlink and symlink staging for local compatibility audit mod zips.
- Added reviewed expected-failure rules for external Factorio `2.1` local-library stress failures.
- Added downloaded dependency-cache support to local Factorio `2.1` audit profiles.
- Tightened load-failure grouping so Factorio error excerpts drive failure classification instead of MIR audit-row text.
- Made `mir.ps1` profile-driven for release, overnight, and local-audit commands with simple path overrides.
- Added PowerShell script quality checks for parsing, duplicate parameters, ignored outputs, and secret-output guards.
- Added Factorio `2.0` and `2.1` run profiles for release gates, overnight sweeps, and local audits.
- Made compatibility audits select the Factorio line, local scenario defaults, and available official built-ins.

## Validation

The final `2.1.5` release gate passed on `main` with:

- Static validation.
- Runtime Factorio fixture validation.
- Deterministic Space Age `AuditSmoke`.
- Targeted local smoke tests for `big-mining-drill` and `biolabs-in-space`.
- Representative local BZ Space Age scenario `local-2-1-bz-suite-space-age`.
- Package rebuild and clean git status.

## Notes

- Recipe productivity still respects Factorio's normal recipe productivity cap.
- Cap diagnostics are warnings only; MIR does not raise, remove, or silently change recipe productivity caps in this release.
- The new compatibility planner rows are diagnostics only; they do not broaden generated gameplay behavior.
- Broader stream candidates such as ore crushing, Air Scrubbing clean-filter productivity, tile/surface productivity, and overhaul material families remain planned work for later releases after explicit fixtures and balance policy.
