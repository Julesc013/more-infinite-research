# M.I.R. TODO

Updated: 2026-07-20

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.9 is the published immutable Factorio 2.1 baseline on `main`.
- MIR 2.4.5 is the published immutable Factorio 2.0 baseline on `legacy`.
- MIR 2.4.9 is the active bounded Factorio 2.0 stability candidate on `tmp/2.0`.
- MIR 2.4.9 contains the Factorio 2.0 capability guard, exhaustive technology-effect target sanitation, reset-safety fix, Space Exploration dangling-recipe repair, steel productivity, material-family scrap-recovery exclusions, and all 50 Factorio locales.
- MIR 3.2.0 remains the canonical Factorio 2.1 development line on `dev`; MIR 2.5.0 is its later independent Factorio 2.0 compiler and verification backport.
- The earlier MIR 2.5.0 package is a superseded implementation checkpoint, not a release artifact.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- 2.4.9 gates: `docs/releases/2.4.9-stability-backport.md`, `docs/releases/notes/release-notes-2.4.9.md`, and `docs/maintainer/release-assurance.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.
- Superseded candidate identity: `.mir/evidence/2.5.0-supersession-ledger.md`.

## Current Gate

1. [x] Backport and fixture the urgent Factorio 2.0 capability, effect-integrity, reset-safety, Space Exploration, steel-productivity, locale, and release-boundary fixes.
2. [ ] Freeze the final package-source commit and build one deterministic MIR 2.4.9 archive.
3. [ ] Regenerate the exact 2.4.5-to-2.4.9 approved delta and run the complete Factorio 2.0 backport plan, upgrade proof, ecosystem lanes, and six-lane paired performance campaign.
4. [ ] Complete the maintainer-authored package review attestation against the exact final archive.
5. [ ] Run protected qualification, create and inspect the candidate seal, then promote the same evidence commit to `legacy` without rebuilding.
6. [ ] Tag and publish the sealed MIR 2.4.9 archive.
7. [ ] Return portable fixes and release-process lessons to `dev`, then resume MIR 3.2.0 and plan the independent MIR 2.5.0 backport.

## Recurring Release Gate

- [ ] `git status --short --branch`
- [ ] `git diff --check`
- [ ] `./scripts/Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] Run the matching Factorio binary matrix and exact prior-release upgrade.
- [ ] Run named ecosystem checks at their supported claim level.
- [ ] Build deterministically and verify package hygiene.
- [ ] Qualify and seal the candidate with content-addressed evidence.
- [ ] Promote the same commit to the stable target branch without rebuilding.
- [ ] Complete maintainer interactive review, tag, and publication.
