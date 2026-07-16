---
title: "Release Assurance And Candidate Sealing"
status: current
applies_to: "2.5.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-07-16
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
./scripts/mir.ps1 assurance doctor --target 2.0 --factorio 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'
./scripts/mir.ps1 verify plan --target 2.0 --baseline <qualified-ref> --profile auto --output out/verification-plan.json
./scripts/mir.ps1 verify explain --target 2.0 --plan out/verification-plan.json --test <stable-id>
```

Each test has one disposition:

| Disposition | Meaning |
| --- | --- |
| `REUSE` | A trusted schema-3 passing capsule exactly matches the current fingerprint |
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
| `F4` | Configuration-change, upgrade, ecosystem, seal, and promotion evidence |

## Evidence Ledger

Evidence lives at `artifacts/assurance/evidence/<safe-test-id>/<fingerprint>/`. `running.json` is an expiring ownership marker. `attempts/*.json` are append-only execution records. `passed.json` is the reusable result for that exact fingerprint. `blocked.json` prevents a prior pass from being reused after a failed attempt against the same inputs.

A schema-3 capsule binds the test ID, target, definition hash, full effective-input map, command, assertions, producer repository and run identity, timestamps, duration, log digest, conclusion, and result digest. A changed definition or input creates a different fingerprint instead of rewriting history.

## Worker And Aggregate Gate

Run one planned test with:

```powershell
./scripts/mir.ps1 verify run-one --target 2.0 --plan out/verification-plan.json --test <stable-id> --fingerprint <sha256> --factorio <factorio.exe>
```

The worker rechecks the exact evidence before execution. If a matching worker is active, it waits and adopts the completed pass. Otherwise it writes `running.json`, executes the command, writes the attempt and pass or block capsule, and clears the marker.

Evaluate the complete plan with:

```powershell
./scripts/mir.ps1 verify gate --target 2.0 --plan out/verification-plan.json --output artifacts/assurance/evidence-bundle.json
```

The gate recomputes the candidate domain manifest when runtime scenarios are present and requires trusted exact passing evidence for every planned fingerprint. Scheduled `--no-reuse` plans additionally require evidence produced after the plan and, in GitHub Actions, by the same workflow run.

## CI

The default workflow is named `MIR`; its aggregate required check is `MIR / verification-gate`. The plan job restores the latest evidence ledger and exports only non-reused work. Worker jobs use fingerprint concurrency with `cancel-in-progress: false`. The gate merges evidence, evaluates the plan, writes the evidence bundle, and saves a new immutable cache key.

Runtime, targeted, full, and scheduled workflows use trusted self-hosted Windows runners. They build one candidate, upload the same bytes to every worker, and never use `pull_request_target`. Self-hosted Factorio binaries, local proprietary mods, publishing credentials, and untrusted fork code must remain isolated.

## Qualification And Sealing

For MIR 2.5.0:

```powershell
./scripts/mir.ps1 assurance build --target 2.0
./scripts/mir.ps1 verify plan --target 2.0 --profile full --factorio 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_2.4.5.zip' --output out/verification-plan.json
./scripts/mir.ps1 verify run --target 2.0 --plan out/verification-plan.json --factorio 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_2.4.5.zip'
./scripts/mir.ps1 verify gate --target 2.0 --plan out/verification-plan.json --output .mir/evidence/2.5.0-assurance-qualification.json
```

After reviewing and committing the exact candidate and qualification record, create and verify the seal:

```powershell
./scripts/mir.ps1 assurance seal --target 2.0 --factorio 'D:\Programs\Factorio\2.0\bin\x64\factorio.exe' --evidence .mir/evidence/2.5.0-assurance-qualification.json
./scripts/mir.ps1 assurance check-seal --seal .mir/evidence/candidate-seals/mir-2.5.0-factorio-2.0.json
```

Promotion checks verify identities and ancestry only. They cannot tag, push, create a GitHub release, or upload to the Mod Portal.

## Backports

Backports recalculate every fingerprint on the target branch. MIR 2.5.0 uses the Factorio 2.0 candidate ZIP, Factorio 2.0 verification profile and binary, target scenario declarations, target fixtures and mod lock, target dependency contract, and exact MIR 2.4.5 prior release. Factorio 2.1 evidence cannot satisfy the Factorio 2.0 aggregate gate even if source files look similar.

Tooling may be ported as one portable change, but target metadata, API adapters, reduced feature decisions, fixtures, archive bytes, and evidence remain target-local. Build the target candidate before planning any matrix that requires package domains.

## Adding Tests Or Domains

Add a permanent test or matrix template to `validation/tests.yml`, declare every effective input, and route it through the appropriate `.mir/assurance.json` change classes. Add package-domain rules or scenario dependencies to `validation/domains.yml`; unmatched package paths must remain conservative. Update `Test-MIRAssurance.ps1`, `.mir/fixtures.yml`, `.mir/modules.yml`, this document, and any affected target profile when the verification contract changes.

## Remaining Human Gates

Interactive GUI locale review, visual truncation review, human balance judgment, Mod Portal presentation review, GitHub release presentation review, and any compatibility campaign without honest automation remain manual. Automated evidence supports those decisions but does not mark them passed.
