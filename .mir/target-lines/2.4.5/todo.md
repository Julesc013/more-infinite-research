# M.I.R. TODO

Updated: 2026-07-14

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.9 is the sealed, unreleased canonical Factorio 2.1 source anchor on `main` at release-candidate commit `9c8f40038e42fda378b855bb8132fd98a180b6a5`; its final harness refresh follows 2.4.5 promotion.
- MIR 2.3.5 is the published Factorio 2.0 predecessor on `legacy`.
- MIR 2.4.0 is published from `legacy` commit `584b398f98d3e317fac31cba63edcb11360a5bb1`.
- MIR 2.4.5 is qualified on `tmp/2.0` as the complete Factorio 2.0 projection of the 3.1.9 portable behavior set.
- The internal MIR 2.5.0 candidate is superseded. Its commit and digest are preserved as safety evidence; its archive and release-facing fixture are removed.
- `tmp/1.1` and every older target remain untouched during the 2.4.5 hotfix run.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- 2.4.5 gates: `docs/releases/2.4.5-checklist.md`, `docs/releases/2.4.5-validation-summary.md`, and `docs/maintainer/release-assurance.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.
- Superseded candidate identity: `.mir/evidence/2.5.0-supersession-ledger.md`.

## Current Gate

1. [x] Prove the disabled Automation science technology regression on Factorio 2.0.
2. [x] Rebuild and rerun version-sensitive exact-archive, upgrade, determinism, and ecosystem checks for 2.4.5.
3. [ ] Push the sealed exact candidate on `tmp/2.0`, then promote the same commit to `legacy` without rebuilding.
4. [ ] Refresh and validate the 3.1.9 harness and exact dist on `main`, then push `main`.
5. [ ] Stop before interactive review, tag creation, publication, `dev` integration, or `tmp/1.1` work.

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
