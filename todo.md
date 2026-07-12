# M.I.R. TODO

Updated: 2026-07-13

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.0.5 and 3.1.0 are published and frozen for Factorio 2.1. Their exact archives must never be rebuilt.
- MIR 2.3.5 is frozen on `legacy`; MIR 2.4.0 is published and frozen on `tmp/2.0` with SHA-256 `8618CAF031EF24EB83641DB03566F2390DD29AD98D2099A80D596EEB527EDA12`.
- MIR 2.5.0 is a qualified, unpublished Factorio 2.0 release candidate: 82/82 scenarios passed and the archive SHA-256 is `0BE57ED4C51DDF08F80AB4CFB2D5762DF2714B17AB26DB58CA9980289350CBFD`.
- `tmp/1.1` has a qualified 1.9.4 candidate. `tmp/1.0` has a staged but unqualified 1.8.2 candidate and still requires valid runtime proof.
- Active `dev` work starts from the immutable 3.1.0 behavior baseline and implements the automatic family compiler contract without altering released bytes.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- Portable lessons: `.mir/portable-return.yml` and `docs/compatibility/portable-return-ledger.md`.
- 2.3.5: `docs/releases/2.3.5-backport-plan.md`, `docs/releases/2.3.5-release-checklist.md`, and `docs/releases/2.3.5-validation-summary.md` on `tmp/2.0`.
- 3.1.0: `docs/releases/3.1.0-plan.md`, `docs/releases/3.1.0-checklist.md`, and `docs/releases/3.1.0-roadmap.md`.
- 2.4.0: `docs/releases/2.4.0-roadmap.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.

## Next Actions

1. Preserve the exact MIR 2.5.0 RC archive and complete interactive release review before any later tag or publication action.
2. Return portable Factorio 2.0 fixes and validation lessons to `dev` without target metadata.
3. Complete old-target qualification and one portable-return fixed-point sweep independently.

## Completed Development Gates

- [x] Pure whole-plan compilation and deferred adoption mutation.
- [x] RecipeFactV2 and shared relationship indexes.
- [x] Data-only FamilyRule registry with existing-stream-only attachment.
- [x] Fixture-only policy removed from production profiles; CompatibilityPack schema active.
- [x] Capability `materialize/result`, central effect metadata, and dependency-enforced commands.
- [x] Scenario manifest schema 2, 70-ID golden plan, static suite, and 83/83 Factorio 2.1 integration matrix.

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
