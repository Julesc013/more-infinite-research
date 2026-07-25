---
title: "Release Process"
status: current
applies_to: "3.0.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# Release Process

Use the canonical assurance plan, exact approved delta, static and runtime qualification, paired performance evidence, package-focused manual attestation, changelog and compatibility-claim review, protected seal, and package hash record before publishing.

## Release Freeze

After a version archive exists under `dist/`, freeze the release branch until publication.

Allowed before publish:

- packaging fix;
- metadata typo;
- changelog formatting fix;
- release-summary correction;
- validation-script correction.

Blocked before publish:

- new capability behavior;
- new compatibility claim;
- new generated stream;
- broad formatting pass;
- stream definition change;
- package-visible copy change that is not followed by a rebuilt archive and updated hash.

## Publish-Candidate Check

Run the publish-candidate preflight from a clean `dev` checkout. Materialize the plan before executing tests:

```powershell
git status
git rev-parse HEAD

.\scripts\mir.ps1 assurance build --target 2.1
.\scripts\mir.ps1 verify plan --target 2.1 --profile full --factorio <factorio-2.1.11.exe> --prior <mir-3.1.9.zip> --output out/verification-plan.json
Get-Content -Raw .\out\verification-plan.json
Get-FileHash .\dist\more-infinite-research_<version>.zip -Algorithm SHA256
git diff --check
git status
```

The full plan expands `runtime.upgrade` into five required archetypes in one schema-bound matrix result. Do not substitute the historical six-assertion native-owner proof. Ecosystem campaign rows and target-qualified local repair smokes must also pass their exact `.mir/sanitation-budgets.json` budget; `REVIEW_REQUIRED` is not a pass.

If README, changelog, locale, or any other package-visible file changes, rebuild `dist/more-infinite-research_<version>.zip`, regenerate candidate-bound evidence, and update the recorded size and SHA-256 before promotion. Do not dispatch the protected workflow until the exact approved delta, runtime performance evidence, and package manual attestation can satisfy F4.

The protected `Assurance Full Qualification` workflow builds once, uses a fresh full plan, runs F0 through F4, evaluates the aggregate gate, and creates a schema-4 seal. Download and inspect the candidate, descriptor, plan, qualification summary, performance evidence, manual attestation, and seal. Rebuild locally and require byte identity; do not publish rebuilt bytes.

GitHub release text, Mod Portal presentation, screenshots, links, and public claims are reviewed after package sealing and before publication. They are not part of the package attestation unless their source is packaged.

## Backport Publication Freeze

For target-line backports, the release branch and `.mir/branches.yml` must record the exact zip that is uploaded.

After a backport is uploaded:

- verify the Mod Portal lists the intended MIR version and Factorio line;
- tag the GitHub source point;
- mark the `.mir/branches.yml` artifact row as `published`;
- treat the uploaded zip as immutable.

Do not rebuild a published backport archive. A changed payload after upload must become the next patch version, such as `2.3.1` after `2.3.0`.

## Main Promotion

Promote `dev` to `main` only after the protected seal and promotion check pass against the same candidate bytes.

Fast-forward flow:

```powershell
git checkout main
git pull --ff-only origin main
git merge --ff-only dev
git push origin main
git checkout dev
```

Release-PR flow:

```text
open dev -> main
do not add features while the PR is open
merge only after the publish-candidate check is current
tag after the final main commit is known
```

Use an annotated tag only after the public candidate bytes match the seal:

```powershell
git tag -a v3.0.0 -m "More Infinite Research 3.0.0"
git push origin v3.0.0
```

## Patch Window

For the first 24 to 72 hours after a major release, use patch releases only for:

- load crash;
- packaging issue;
- wrong dependency metadata;
- migration or save issue;
- incorrect package contents;
- release-note correction;
- false positive in the strict architecture gate.

Do not add broad generation, new capability emissions, new stream IDs, or broad compatibility claims in the first patch window.

## Current-Line Emergency Patch Policy

Do not cut `3.0.1` unless the Factorio `2.1` current line has a real release-blocking issue:

- serious load failure;
- broken save migration;
- generated technology ID problem;
- package hygiene issue that affects users;
- materially wrong public upload;
- critical compatibility fix that is already validated.

All other portable lessons from target-line backports accumulate on `dev` for `3.0.5`.
