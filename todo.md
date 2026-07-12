# M.I.R. TODO

Updated: 2026-07-12

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.0 is published and frozen on the Factorio 2.1 line. GitHub contains the exact archive; Mod Portal upload remains blocked on an upload-scoped API key.
- MIR 2.3.5 is tagged and frozen on `legacy` with SHA-256 `97B3DC9B6E352C6C4B8FF76D77020333FAAFFE93BD89EDB6B8F3370405ED68DE`; external upload status remains explicit.
- MIR 2.4.0 is published and frozen on `tmp/2.0` from the accepted 3.1.0 anchor with SHA-256 `8618CAF031EF24EB83641DB03566F2390DD29AD98D2099A80D596EEB527EDA12`.
- All 78 Factorio 2.0 scenarios, the release-targeted gate, exact base/Space Age archive loads, the 2.3.5 upgrade, freshness, interactive review, and downloaded GitHub asset verification pass. Mod Portal upload remains blocked on an upload-scoped API key.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- Portable lessons: `.mir/portable-return.yml` and `docs/compatibility/portable-return-ledger.md`.
- 2.3.5: `docs/releases/2.3.5-backport-plan.md`, `docs/releases/2.3.5-release-checklist.md`, and `docs/releases/2.3.5-validation-summary.md` on `legacy`.
- 3.1.0: `docs/releases/3.1.0-plan.md`, `docs/releases/3.1.0-checklist.md`, and `docs/releases/3.1.0-roadmap.md`.
- 2.4.0: `docs/releases/2.4.0-roadmap.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.

## Next Actions

1. Keep the immutable 3.1.0, 2.3.5, and 2.4.0 release bytes frozen on `dev`/`main`, `legacy`, and `tmp/2.0` respectively.
2. Carry the generic Factorio 2.0 validation and fixture portability lessons in the portable-return ledger for the next `dev` development release; do not rewrite released 3.1.0 evidence or return Factorio 2.0 metadata and feature cuts.
3. Replay the final portable patch set to older targets only through their declared target profiles and matching binary gates.
4. Complete one descending target fixed-point sweep before declaring the broader historical backport wave closed.

## Recurring Release Gate

- [ ] `git status --short --branch`
- [ ] `git diff --check`
- [ ] `./scripts/Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] Run the matching Factorio binary matrix.
- [ ] Run the matching release-targeted profile against its local mod library.
- [ ] Load the exact frozen archive in base and expansion configurations.
- [ ] Run the prior-release save upgrade when one exists.
- [ ] Verify candidate freshness from a clean tree.
- [ ] Complete interactive save/settings review.
- [ ] Publish the exact validated bytes without rebuilding.
