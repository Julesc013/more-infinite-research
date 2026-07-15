---
title: "Release Assurance And Candidate Sealing"
status: current
applies_to: "3.1.9+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-14
supersedes: []
superseded_by: []
---

# Release Assurance And Candidate Sealing

MIR release assurance uses an immutable qualified-candidate seal plus dependency-based evidence invalidation. The seal binds one exact ZIP to its package-source tree, content hash, target profile, test catalog, validation harness, Factorio binary, and qualification summary. A later promotion check verifies those identities; it never rebuilds or publishes the candidate.

## Architecture

| Component | Purpose | Inputs | Outputs | Package impact |
| --- | --- | --- | --- | --- |
| Impact engine | Select invalidated evidence conservatively | Git diff, ownership rules, package files | Classified paths and test plan | None |
| Test catalog | Give release-blocking tests stable IDs and declared inputs | `.mir/test-catalog.json` | Dependency graph | None |
| Evidence store | Retain complete content-addressed proof | Artifact, binary, harness, fixtures, settings | Evidence capsules | None |
| Candidate seal | Freeze qualified bytes and proof | Exact ZIP and qualification summary | `SEALED-RC` record | None |
| Locale validator | Validate catalogs and placeholders | Locale and setting descriptors | Locale evidence | None unless locale is packaged |
| Balance workbench | Fingerprint progression authorities | Stream, setting, cost, and native-owner descriptors | Balance snapshot | None |
| Runtime harness | Exercise the exact ZIP | Factorio binary, ZIP, fixtures | Runtime evidence | None |
| CI orchestration | Share one plan across jobs | Assurance plan | Aggregated evidence | None |

The command implementation is `scripts/Invoke-MIRAssurance.ps1`, exposed through `scripts/mir.ps1 assurance`. The shorter `scripts/mir.ps1 verify` surface maps `plan`, `explain`, `run`, and `qualify` onto the same assurance implementation and evidence graph; it does not create a second verifier. `.mir/assurance.json` owns change classes and profiles. `.mir/test-catalog.json` owns test IDs, commands, and declared inputs. These tools, manifests, evidence, docs, fixtures, workflows, and candidate seals are excluded from the Factorio release ZIP.

## Required Runbook

Start every release or backport with:

```powershell
./scripts/mir.ps1 assurance doctor --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
./scripts/mir.ps1 assurance inventory --output artifacts/assurance/inventory.json
./scripts/mir.ps1 assurance impact --baseline <qualified-commit> --json
./scripts/mir.ps1 verify plan --baseline <qualified-commit> --profile auto --output artifacts/assurance/plan.json
```

Inspect the plan before executing expensive jobs. Run the plan through `verify`, or use `qualify --profile full` for a release candidate. Recalculate impact after every source change. Rebuild only when a package input changes. Never hand-edit an evidence capsule or seal to green.

## Change Classes

| Class | Fingerprints | Mandatory evidence | Factorio rule | Escalation |
| --- | --- | --- | --- | --- |
| Promotion only | Seal, ZIP, evidence, commit ancestry | `seal.verify` | None | Any identity mismatch blocks |
| Repository docs | Package-source hash and docs governance | `docs.check`, seal verification | None while ZIP and package source are unchanged | Generated/package drift broadens |
| Test or CI tooling | Catalog and harness hashes | Tool self-tests plus every changed dependent gate | Dependent runtime gates rerun | Unknown dependency broadens |
| Packaged non-runtime | ZIP and content hashes | Deterministic package and exact-ZIP smoke | Exact ZIP load | Semantic drift broadens |
| Locale | Locale catalog, placeholders, ZIP | Full locale audit, package check, exact-ZIP load | Exact ZIP load on affected target | Descriptor or setting drift broadens |
| Metadata/dependencies | `info.json`, dependency closure, ZIP | Package and dependency validation, upgrade when version behavior changes | Full exact-ZIP load | Unknown dependency broadens |
| Balance/prototype values | Stream, setting, cost, generated-manifest fingerprints | Balance snapshot, compiler checks, affected runtime scenarios | Required | Unexplained diff blocks |
| Compiler/data stage | Package source, compiler plans, harness | Compiler and architecture gates, affected/full matrix, exact ZIP | Required | Failed equivalence or unknown impact selects full |
| Settings | Settings descriptors, locale, profiles, migrations | Settings, locale, compiler, retention, upgrade, exact ZIP | Required | Missing migration/visibility proof selects full |
| Runtime/migration | Runtime source, save fixtures, binary, harness | Complete runtime and upgrade matrix | Required | No non-runtime fast path |
| Unknown | All available fingerprints | Full target qualification | Required | Always full |

Path matching contributes to classification but never proves harmlessness. Package-source, ZIP-content, catalog, harness, target-profile, setting, fixture, and binary fingerprints decide whether prior evidence remains valid.

## Evidence Keys And Reuse

Every evidence capsule includes the stable test ID, exact candidate hash, Factorio binary hash when applicable, test-catalog hash, harness hash, target, command, first result, duration, and message. Changing the test implementation, binary, fixture, settings, candidate, or relevant catalog input produces a different evidence key and invalidates reuse. A failure stays a failure; a diagnostic rerun is separate evidence and cannot erase the first result.

Repository-only documentation can reuse runtime evidence only when the package-source and candidate hashes remain exact. Locale changes require locale proof and an exact-ZIP load but may reuse gameplay simulation. Compiler refactors may reuse broad gameplay evidence only when canonical compiler outputs, package semantics, settings, runtime handlers, and migration inputs are identical and the explicit refactor-equivalence profile passes. Runtime and migration changes never use that route.

## Locale Workflow

Use `./scripts/mir.ps1 assurance locale` during editing. Candidate qualification runs the complete locale catalog and exact-ZIP load selected by the impact plan. Placeholder corruption, missing canonical keys, malformed sections, unavailable-setting visibility drift, and target-specific locale drift are blocking. Pseudo-locale screenshots and visual truncation remain human gates.

## Balance Workflow

Use `./scripts/mir.ps1 assurance balance --output artifacts/assurance/balance-snapshot.json` before and after balance work. Review the stream, generated-manifest, setting, generated-cost, native-owner source, formula-adapter, binding, and transaction fingerprints. `.mir/native-owner-cost-models.json` records the reviewed Factorio source digest and native values that default-preservation fixtures protect. An undeclared fingerprint change blocks promotion until the affected streams, scenarios, release notes, and reviewed balance intent agree. Static formula checks speed the loop; they do not replace target runtime evidence or human progression judgment.

## Refactors And Hotfixes

For a behavior-preserving refactor, use `--profile refactor-equivalence`, compare canonical plans and generated outputs, then run the exact ZIP. If any semantic fingerprint changes, use the compiler/data-stage route. For a hotfix, diff from the exact released source and ZIP, select the direct regression and neighboring tests, run breadth canaries, build once, run required load/reload or upgrade checks, and create a new seal. Unknown impact blocks promotion.

## Full Qualification And Sealing

Build the exact candidate once and pass the same bytes to every downstream check:

```powershell
./scripts/mir.ps1 assurance qualify --target 2.1 --profile full --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.5.zip' --output .mir/evidence/3.1.9-assurance-qualification.json
# Review and commit the exact candidate archive and qualification summary before sealing.
./scripts/mir.ps1 assurance seal --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --evidence .mir/evidence/3.1.9-assurance-qualification.json
./scripts/mir.ps1 assurance check-seal --seal .mir/evidence/candidate-seals/mir-3.1.9-factorio-2.1.json
```

The promotion check verifies the seal, exact ZIP, package source, target profile, test catalog, harness, evidence hash, and source ancestry. It cannot tag, push a tag, create a GitHub release, or upload to the Mod Portal.

## Backport Qualification

Each target is an independent implementation. Run `assurance backport --target <line> --baseline <source>` to produce the target plan, then qualify with the matching binary, target fixtures, exact prior release passed through `--prior`, settings-retention route, and ecosystem profile. Evidence from another Factorio line is never substituted. Tooling-only commits may share orchestration, but every target receives a new bootstrap qualification and target seal. Confirm the tooling commit does not change package-source or ZIP hashes.

## Adding A Test, Compiler Module, Or Target

Add a test by assigning a permanent ID in `.mir/test-catalog.json`, declaring its complete inputs, command, Factorio requirement, and every change class that selects it. Extend `Test-MIRAssurance.ps1` when a new invalidation boundary is introduced. Add a compiler module through the governed provider/family contracts, update `.mir/modules.yml`, declare positive and negative fixtures, update affected change classes, and preserve emission-only prototype mutation. Add a target through `.mir/targets.json`, synchronize generated target profiles, register its binary capabilities and run profile, add prior-version upgrade evidence, and require its own seal.

## CI And Security

The always-running `MIR Verify / verify` workflow materializes the change-aware plan and runs the fast static gate on trusted pushes and pull requests. Targeted and full qualification jobs require trusted runners with the matching Factorio binary. Scheduled breadth checks detect fixture and environment drift. Promotion jobs only verify seals. Backport jobs keep per-target artifacts and evidence isolated.

Self-hosted runners containing Factorio binaries or proprietary mods must never execute untrusted fork code. Do not use `pull_request_target` to run submitted source. Use least-privilege read permissions, explicit trusted dispatch for runtime work, content-addressed caches, isolated user-data directories, scrubbed logs, and no publishing credentials in validation workflows. A cache key named `latest`, mutable green status, missing evidence manifest, or hash mismatch is invalid and must be discarded.

## Troubleshooting

An unexpected full gate normally means an unclassified path or a changed catalog/harness fingerprint. Run `assurance explain --baseline <ref> --json` and classify the input rather than overriding the plan downward. A seal mismatch reports the failed identity; restore the exact sealed bytes or requalify and issue a new seal. A test-harness change invalidates affected results even when the mod ZIP is unchanged. A Factorio binary replacement invalidates all evidence bound to the previous binary hash.

## Remaining Human Gates

Interactive GUI locale review, visual truncation review, human balance judgment, Mod Portal presentation review, GitHub release presentation review, and any campaign step that lacks honest automation remain manual. Automated evidence may support these gates but must never mark them passed.
