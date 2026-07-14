# M.I.R. TODO

Updated: 2026-07-14

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.5 is the published canonical Factorio 2.1 anchor at release commit `c8bf4a742910cec9d6d3dee305c83deba1aa49eb`.
- MIR 2.3.5 is the published Factorio 2.0 predecessor on `legacy`.
- MIR 2.4.0 is published from `legacy` commit `584b398f98d3e317fac31cba63edcb11360a5bb1`.
- MIR 2.4.1 is active on `tmp/2.0` as the disabled-prerequisite startup-safety hotfix.
- The internal MIR 2.5.0 candidate is superseded. Its commit and digest are preserved as safety evidence; its archive and release-facing fixture are removed.
- `tmp/1.1` and every older target remain untouched during the 2.4.1 hotfix run.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- 2.4.1 gates: `docs/releases/2.4.1-checklist.md`, `docs/releases/2.4.1-validation-summary.md`, and `docs/maintainer/release-assurance.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.
- Superseded candidate identity: `.mir/evidence/2.5.0-supersession-ledger.md`.

## Current Gate

1. [x] Prove the disabled Automation science technology regression on Factorio 2.0.
2. [x] Run the affected validation, exact-archive smokes, and deterministic package checks for 2.4.1.
3. [x] Seal and push the exact candidate on `tmp/2.0`.
4. [x] Stop before interactive review, tag creation, or publication.

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
