# M.I.R. TODO

Updated: 2026-07-14

This file is the concise executable queue. Detailed scope, decisions, evidence, and target state live in the governed records linked below.

## Current Truth

- MIR 3.1.5 is the published canonical Factorio 2.1 anchor at release commit `c8bf4a742910cec9d6d3dee305c83deba1aa49eb`.
- MIR 2.3.5 is the published Factorio 2.0 predecessor on `legacy`.
- MIR 2.4.0 is reopened on `tmp/2.0` for the native-owner settings repair. The pre-repair seal is superseded, and no 2.4.0 candidate is currently qualified, tagged, or published.
- The internal MIR 2.5.0 candidate is superseded. Its commit and digest are preserved as safety evidence; its archive and release-facing fixture are removed.
- `tmp/1.1` and every older target remain untouched until the maintainer tags and publishes 2.4.0.

## Authoritative Records

- Release wave: `.mir/release-wave.yml` and `docs/releases/backport-wave-dashboard.md`.
- 2.4.0 gates: `docs/releases/2.4.0-checklist.md`, `docs/releases/2.4.0-validation-summary.md`, and `docs/maintainer/release-assurance.md`.
- Branch and target policy: `.mir/branches.yml`, `.mir/targets.json`, and `docs/maintainer/backporting.md`.
- Superseded candidate identity: `.mir/evidence/2.5.0-supersession-ledger.md`.

## Current Gate

1. Implement the class-wide native-owner configuration contract and expanded fixtures.
2. Rebuild, fully requalify, and reseal the exact 2.4.0 candidate.
3. Promote the sealed candidate and exact archive to `legacy`; verify without rebuilding.
4. Push the non-release branches and stop.
5. Leave interactive review, the existing local tag collision, final tag creation, and publication to the maintainer.

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
