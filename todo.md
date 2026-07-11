# M.I.R. TODO

Updated: 2026-07-12

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.0.5 is published and frozen. Its archive SHA-256 is `40AF95C3F4411DDF6C24C98897489D696339A1B85B0439FA4A3BDFEDDDF0E5C5`; never rebuild it.
- MIR 2.3.5 is qualified on `tmp/2.0` at evidence commit `7588eadc18f49f60d17d145ce366b5a777d9be43`. Its frozen candidate archive SHA-256 is `97B3DC9B6E352C6C4B8FF76D77020333FAAFFE93BD89EDB6B8F3370405ED68DE`.
- The 2.3.5 automated, release-targeted, exact-dist base/Space Age, and 2.3.0 upgrade gates pass. Interactive settings UI and retained-value inspection remains before promotion, tag, or publication.
- Package-visible 3.1 implementation does not start until 2.3.5 is published and frozen.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- Portable lessons: `.mir/portable-return.yml` and `docs/compatibility/portable-return-ledger.md`.
- 2.3.5: `docs/releases/2.3.5-backport-plan.md`, `docs/releases/2.3.5-release-checklist.md`, and `docs/releases/2.3.5-validation-summary.md` on `tmp/2.0`.
- 3.1.0: `docs/releases/3.1.0-plan.md`, `docs/releases/3.1.0-checklist.md`, and `docs/releases/3.1.0-roadmap.md`.
- 2.4.0: `docs/releases/2.4.0-roadmap.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.

## Next Actions

1. Inspect the exact 2.3.5 archive in the Factorio 2.0 startup settings UI, confirm retained weapon/profile values and recycler/cap/scope independence, then record acceptance without rebuilding.
2. Promote the exact 2.3.5 candidate to `legacy`, rerun freshness, tag, upload, verify public Factorio 2.0 visibility, and mark the archive published/frozen.
3. Create `pre-3.1-modernization` from released 3.0.5 plus accepted portable-return records.
4. Execute the 3.1 plan in dependency order and stop at every release gate.
5. Create 2.4.0 from the accepted 3.1 source anchor and apply only positive Factorio 2.0 target cuts.
6. Replay the final portable patch set to older targets and complete a fixed-point sweep.

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
