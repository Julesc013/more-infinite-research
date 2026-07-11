# M.I.R. TODO

Updated: 2026-07-12

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.0 is published and frozen on the Factorio 2.1 line. GitHub contains the exact archive; Mod Portal upload remains blocked on an upload-scoped API key.
- MIR 2.3.5 is tagged and frozen on `legacy` with SHA-256 `97B3DC9B6E352C6C4B8FF76D77020333FAAFFE93BD89EDB6B8F3370405ED68DE`; external upload status remains explicit.
- MIR 2.4.0 is implemented on `tmp/2.0` from the accepted 3.1.0 anchor. All 78 Factorio 2.0 scenarios, the release-targeted gate, exact base/Space Age archive loads, and the 2.3.5 upgrade pass.
- Final 2.4.0 source binding, freshness, interactive review, promotion, and publication remain.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- Portable lessons: `.mir/portable-return.yml` and `docs/compatibility/portable-return-ledger.md`.
- 2.3.5: `docs/releases/2.3.5-backport-plan.md`, `docs/releases/2.3.5-release-checklist.md`, and `docs/releases/2.3.5-validation-summary.md` on `tmp/2.0`.
- 3.1.0: `docs/releases/3.1.0-plan.md`, `docs/releases/3.1.0-checklist.md`, and `docs/releases/3.1.0-roadmap.md`.
- 2.4.0: `docs/releases/2.4.0-roadmap.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.

## Next Actions

1. Bind the final 2.4.0 package-visible source and exact archive to one clean structured validation run.
2. Complete exact-archive interactive save and startup-settings inspection without rebuilding.
3. Promote the accepted 2.4.0 source to `legacy`, tag, publish the exact archive where credentials permit, and freeze it.
4. Return generic validation and fixture portability fixes to `dev` without returning Factorio 2.0 metadata or feature cuts.
5. Replay the final portable patch set to older targets and complete a fixed-point sweep.

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
