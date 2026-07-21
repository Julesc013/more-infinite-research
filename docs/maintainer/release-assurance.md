---
title: "Release Assurance And Candidate Sealing"
status: current
applies_to: "3.2.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# Release Assurance And Candidate Sealing

MIR release assurance is a persistent content-addressed evidence system. It plans stable test instances from effective inputs, reuses only trusted exact passing proof, adopts matching in-progress workers, and evaluates one aggregate gate. Candidate sealing remains a separate promotion step that binds one exact qualified ZIP and evidence bundle; sealing never rebuilds or publishes.

## Authorities

| Authority | Owns |
| --- | --- |
| `.mir/assurance.json` | Change classes, profiles, canonical verifier paths, aggregate gate name |
| `validation/tests.yml` | Stable test IDs, commands, Factorio layers, scenario-matrix templates, declared input tokens |
| `validation/domains.yml` | Package domains, scenario dependency sets, dependency-contract normalization, unknown-input fallback |
| `validation/profiles/factorio-<target>.json` | Target policy, deterministic seed, evidence TTL, upgrade source and fixture |
| `validation/trust.json` | Evidence trust classes and protected release producer requirements |
| `verification/schema/*.schema.json` | Strict test, plan, result, capsule, bundle, and seal contracts |
| `fixtures/compat-matrix/expected-scenarios.json` | Stable Factorio scenario records, fixtures, settings, assertions, groups, tags, isolation |
| `scripts/Invoke-MIRAssurance.ps1` | Planner, fingerprinting, ledger, worker, aggregate gate, qualification, seal facade |
| `artifacts/assurance/evidence` | Persistent local or CI-restored evidence ledger |
| `out/verification-plan.json` | Reviewable plan for one candidate and target |

`tools/mir_verify/Invoke-MIRVerify.ps1` is only a forwarding entrypoint. It does not implement a second verifier.

## Operating Rule

Before running tests, materialize or inspect the verification plan. Run only the work listed by the plan unless a broader profile or `--no-reuse` was explicitly requested. Reuse a pass only when its stable test ID, target, definition, effective inputs, producer repository, and result digest match exactly. If another worker owns the same fingerprint, wait for and adopt its result; do not cancel it to start duplicate work. Never mark a mutable job status green in place of evidence.

## Plan And Dispositions

Use:

```powershell
./scripts/mir.ps1 assurance doctor --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
./scripts/mir.ps1 verify plan --target 2.1 --baseline <qualified-ref> --profile auto --output out/verification-plan.json
./scripts/mir.ps1 verify explain --target 2.1 --plan out/verification-plan.json --test <stable-id>
```

Each test has one disposition:

| Disposition | Meaning |
| --- | --- |
| `REUSE` | A same-trust-class schema-4 passing capsule exactly matches the current fingerprint and structured output |
| `WAIT` | A non-expired `running.json` shows another worker owns the same fingerprint |
| `RUN` | No exact evidence exists or reuse was disabled |
| `INVALID` | Evidence material exists but is failed, blocked, malformed, untrusted, or digest-mismatched |

Unknown repository inputs escalate through `.mir/assurance.json`. Unknown packaged paths are included in every scenario dependency set, conservatively invalidating the scenario matrix.

## Fingerprint Model

The release artifact and gameplay proof are separate identities. `artifact.sha256` binds exact ZIP bytes. Package domains bind normalized groups of packaged files: `data`, `balance`, `settings`, `runtime`, `migrations`, `locale`, `assets`, `metadata`, `release-text`, and `unknown`. `dependency-contract` hashes the mod name, Factorio target, and dependency declarations while deliberately excluding the MIR version.

This separation is intentional. A version-only change invalidates deterministic packaging, exact-ZIP loads, and upgrade proof because the artifact changed. It does not invalidate a gameplay scenario whose declared data, balance, settings, assets, dependency contract, fixture, harness, Factorio binary, and scenario record are unchanged.

Factorio layers are:

| Layer | Scope |
| --- | --- |
| `F0` | Static validation and contract checks |
| `F1` | Deterministic package construction |
| `F2` | Exact archive load checks |
| `F3` | Data-stage and gameplay scenarios keyed by declared domains |
| `F4` | Configuration-change, upgrade, ecosystem, approved-delta, performance, manual-review, seal, and promotion evidence |

## Evidence Ledger

Evidence lives at `artifacts/assurance/evidence/<safe-test-id>/<fingerprint>/`. `running.json` is an expiring ownership marker. `attempts/*.json` are append-only execution records. `passed.json` is the reusable result for that exact fingerprint. `blocked.json` prevents a prior pass from being reused after a failed attempt against the same inputs.

A schema-4 capsule binds the test ID, target, definition hash, full effective-input map, exact Factorio installation and resolved mod closure when applicable, trust-class-validated producer identity, exit code, structured `mir-test-result-v1`, assertion outcomes, artifact hashes, stdout and stderr hashes, timestamps, duration, and result digest. `passed.json` is only an atomic pointer to an immutable attempt capsule. Corrupt pointers are quarantined. A changed definition, verifier, policy, binary, mod archive, candidate, or other effective input creates a different fingerprint instead of rewriting history.

## Worker And Aggregate Gate

Run one planned test with:

```powershell
./scripts/mir.ps1 verify run-one --target 2.1 --plan out/verification-plan.json --test <stable-id> --fingerprint <sha256> --factorio <factorio.exe>
```

The worker rechecks the exact evidence before execution. If a matching worker is active, it waits and adopts the completed pass. Otherwise it writes `running.json`, executes the command, writes the attempt and pass or block capsule, and clears the marker.

Evaluate the complete plan with:

```powershell
./scripts/mir.ps1 verify gate --target 2.1 --plan out/verification-plan.json --output artifacts/assurance/evidence-bundle.json
```

Every worker and the gate reconstruct the canonical schema-4 plan from the named profile and current authorities, reject missing, extra, duplicate, stale, or altered test entries, and compare the immutable plan-material digest. The gate recomputes the candidate domain manifest when runtime scenarios are present and requires trusted exact passing evidence for every planned fingerprint. Each forced test records its minimum completion time, run ID, and run attempt rather than inheriting plan-wide freshness only.

## CI

The default workflow is named `MIR`; its aggregate required check is `MIR / verification-gate`. The protected full workflow enforces the execution DAG `F0 -> F1 -> F2 -> F3 -> F4 -> gate -> seal`. Its plan is always fresh, uploads only the exact planned candidate, the verification plan, and the candidate descriptor, and never transfers historical distribution archives. Each worker starts without the shared ledger and uploads only its immutable fingerprint capsule plus any structured scenario result. The gate restores the reusable ledger once, merges those capsule deltas by exact fingerprint, evaluates the plan, writes the evidence bundle, and saves one updated immutable cache key.

Runtime, targeted, full, and scheduled workflows use trusted self-hosted Windows runners. They build one candidate, upload the same bytes to every worker, and never use `pull_request_target`. Self-hosted Factorio binaries, local proprietary mods, publishing credentials, and untrusted fork code must remain isolated.

## Qualification And Sealing

For MIR 3.2.0:

```powershell
./scripts/mir.ps1 assurance build --target 2.1
./scripts/mir.ps1 verify plan --target 2.1 --profile full --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip' --output out/verification-plan.json
./scripts/mir.ps1 verify run --target 2.1 --plan out/verification-plan.json --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip'
./scripts/mir.ps1 verify gate --target 2.1 --plan out/verification-plan.json --output artifacts/assurance/3.2.0-assurance-qualification.json
```

The canonical full and backport profiles cannot pass F4 until all of these release authorities bind the exact candidate:

- `release.approved-delta` checks both archive and package-content hashes plus package source authority;
- `runtime.performance-regression` checks the paired qualified-baseline campaign in `.mir/evidence/<version>-performance-regression.json`;
- `manual.release-review` checks the package-focused attestation in `.mir/evidence/<version>-manual-review-attestation.json`.

Schema-3 performance evidence must bind the exact prior release, candidate, source commit, Factorio binary, machine, mod closure, settings, scenarios, and harness. It uses at least one warm-up and five balanced measured pairs. Every governed lane must meet the 20 percent median ceiling or its small absolute-noise allowance, and any declared absolute ceiling. It also preserves maximum-observed compiler artifact-volume counters plus the telemetry fingerprint for every measured diagnostics-off and diagnostics-on candidate run, so timing changes can be separated from plan, coverage, context-copy, closure-cache, and sanitation volume.

Create that evidence with the governed producer before rerunning the full plan:

```powershell
.\scripts\Measure-MIRPerformanceRegression.ps1 `
  -Candidate artifacts\candidate\more-infinite-research_3.2.0.zip `
  -PriorRelease dist\more-infinite-research_3.1.9.zip `
  -FactorioBin C:\Factorio-2.1.11\bin\x64\factorio.exe `
  -LocalModZipDir C:\Factorio-mods-2.1 `
  -ExpectedSourceCommit (git rev-parse HEAD)
```

The campaign uses the non-shipped `fixtures/performance-regression-probe` symmetrically for exact-archive diagnostics-off phase timing. The probe does not enter either release ZIP. Medium and large ecosystem lanes remain load observations over their exact resolved closures.

The manual attestation must be schema 2, passed, self-hashed, tied to the exact candidate bytes, package-content hash, source commit, and qualified Factorio binary, and contain reviewer, time, notes, and portable hashed artifacts for every package checklist item. After reviewing and committing the exact candidate and qualification record, create and verify the seal:

`runtime.upgrade` is one F4 matrix result with five mandatory, independently hashed rows: base/default, Space Age native owner, automatic family creation, base continuation, and mod-set configuration change. The configuration-change row removes its source-only compatibility fixture before loading the candidate and proves current research, fractional progress, generated lifecycle state, and removal of only the dangling recipe target.

Ecosystem evidence is candidate-bound: the release-targeted gate must pass the exact candidate ZIP through every local repair and representative scenario and must not rebuild distribution bytes during verification. The composed `runtime.ecosystem` lane skips the release-gate clean-tree check because source authority is independently enforced by approved-delta, manual-attestation, and protected sealing gates. Ecosystem evidence is also bounded by `.mir/sanitation-budgets.json`. Manifest scenarios resolve through the `campaigns` scope, while target-qualified release repair smokes resolve through `local_mod_zips`. A scenario passes only when its observed external prunes exactly include every reviewed prune and contain no more than the declared maximum unreviewed prunes. Release budgets use zero; a missing budget or mismatch is `REVIEW_REQUIRED`, never a compatibility pass.

```powershell
./scripts/mir.ps1 assurance seal --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip' --plan out/verification-plan.json
./scripts/mir.ps1 assurance check-seal --seal .mir/evidence/candidate-seals/mir-3.2.0-factorio-2.1.json
```

Seal schema 4 binds the performance-evidence and manual-attestation paths, file hashes, and passed statuses. `check-seal` revalidates those bindings along with the candidate, plan, bundle, verifier, producer, and source identities. Promotion checks cannot tag, push, create a GitHub release, or upload to the Mod Portal.

## Backports

Backports recalculate every fingerprint on the target branch. MIR 2.5.0 uses the Factorio 2.0 candidate ZIP, Factorio 2.0 verification profile and binary, target scenario declarations, target fixtures and mod lock, target dependency contract, and exact MIR 2.4.9 prior release. Factorio 2.1 evidence cannot satisfy the Factorio 2.0 aggregate gate even if source files look similar.

Tooling may be ported as one portable change, but target metadata, API adapters, reduced feature decisions, fixtures, archive bytes, and evidence remain target-local. Build the target candidate before planning any matrix that requires package domains.

## Adding Tests Or Domains

Add a permanent test or matrix template to `validation/tests.yml`, declare every effective input, and route it through the appropriate `.mir/assurance.json` change classes. Add package-domain rules or scenario dependencies to `validation/domains.yml`; unmatched package paths must remain conservative. Update `Test-MIRAssurance.ps1`, `.mir/fixtures.yml`, `.mir/modules.yml`, this document, and any affected target profile when the verification contract changes.

## Human Gate Boundary

The pre-seal package review covers technology-tree layout, icons, locale fit and truncation, settings UX, save UI, and human balance judgment. It is a required F4 input and must be attested against the exact package candidate.

GitHub release text, Mod Portal presentation, screenshots, links, and final public claims are a separate pre-publication review. They do not block creation of a sealed package candidate, but publication must not proceed while they remain pending. Any compatibility campaign without honest automation also remains manual and cannot be converted into a support claim by the package attestation.
