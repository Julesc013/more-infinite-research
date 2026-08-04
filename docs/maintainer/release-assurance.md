---
title: "Release Assurance And Candidate Sealing"
status: current
applies_to: "3.2.0+"
audience: release-manager
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: []
superseded_by: []
---

# Release Assurance And Candidate Sealing

MIR release assurance is a persistent content-addressed evidence system. It plans stable test instances from effective inputs, reuses only trusted exact passing proof, adopts matching in-progress workers, and evaluates one aggregate gate. Candidate sealing remains a separate promotion step that binds one exact qualified ZIP and evidence bundle; sealing never replaces or publishes the candidate archive.

## Authorities

| Authority | Owns |
| --- | --- |
| `.mir/assurance.json` | Change classes, profiles, canonical verifier paths, aggregate gate name |
| `validation/tests.yml` | Stable test IDs, commands, Factorio layers, scenario-matrix templates, declared input tokens |
| `validation/domains.yml` | Package domains, scenario dependency sets, dependency-contract normalization, unknown-input fallback |
| `validation/profiles/factorio-<target>.json` | Target policy, deterministic seed, evidence TTL, upgrade source and fixture |
| `validation/trust.json` | Evidence trust classes and protected release producer requirements |
| `spec/schemas/*.schema.json` | Strict test, plan, result, capsule, bundle, and seal contracts |
| `validation/scenarios/runtime.json` | Stable Factorio scenario records, fixtures, settings, assertions, groups, tags, isolation |
| `scripts/Invoke-MIRAssurance.ps1` | Planner, fingerprinting, ledger, worker, aggregate gate, qualification, seal facade |
| `artifacts/assurance/evidence` | Persistent local or CI-restored evidence ledger |
| `out/verification-plan.json` | Reviewable plan for one candidate and target |

`tools/mir_verify/Invoke-MIRVerify.ps1` is only a forwarding entrypoint. It does not implement a second verifier.

## Operating Rule

Before running tests, materialize or inspect the verification plan. Run only the work listed by the plan unless a broader profile or `--no-reuse` was explicitly requested. Reuse a pass only when its stable test ID, target, definition, effective inputs, producer repository, and result digest match exactly. If another worker owns the same fingerprint, wait for and adopt its result; do not cancel it to start duplicate work. Never mark a mutable job status green in place of evidence.

## Plan And Dispositions

Use:

```powershell
./tools/mir.ps1 assurance doctor --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
./tools/mir.ps1 verify plan --target 2.1 --baseline <qualified-ref> --profile auto --output out/verification-plan.json
./tools/mir.ps1 verify explain --target 2.1 --plan out/verification-plan.json --test <stable-id>
```

Each test has one disposition:

| Disposition | Meaning |
| --- | --- |
| `REUSE` | A same-trust-class schema-4 passing capsule exactly matches the current fingerprint and structured output |
| `WAIT` | A non-expired `running.json` shows another worker owns the same fingerprint |
| `RUN` | No exact evidence exists or reuse was disabled |
| `INVALID` | Evidence material exists but is failed, blocked, malformed, untrusted, or digest-mismatched |

Unknown repository inputs escalate through `.mir/assurance.json`. Unknown packaged paths are included in every scenario dependency set, conservatively invalidating the scenario matrix.

The current target profile must exactly match the active typed release record's public upgrade source, target, and fixture. Historical releases continue to receive release-specific projected profiles, but the development planner may not fall back to an older public transition. A declared external input whose fingerprint is `missing` makes that exact plan row `INVALID`; the runner must not discover a missing prior archive, candidate, Factorio installation, or mod closure only after execution starts.

Before focused qualification, `release.approved-delta` binds the active release record and the exact future transition path as `pending`; this is development-state proof that approved-delta authority has not been created. It does not create a delta artifact or an approval claim. Once the release leaves the pre-qualification states, the exact transition artifact must exist and becomes the fingerprinted input.

`development-breadth` is the canonical fresh pre-candidate campaign. It includes every development-valid static, exact-ZIP, full runtime, upgrade, ecosystem, and approved-delta row, but deliberately excludes candidate-bound performance, manual-review, and seal authority. Use it with `--no-reuse` for a complete development calibration. `full` remains the release profile and must continue to fail closed when its exact manual attestation or other candidate inputs are absent.

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

Evidence lives at `artifacts/assurance/evidence/<safe-test-id>/<fingerprint>/`. `running.json` is an expiring ownership marker. `attempts/*.json` are append-only execution records. `passed.json` is the reusable result for that exact fingerprint. `blocked.json` prevents a prior pass from being reused after a failed attempt against the same inputs. Worker-supplied pointers are never aggregate authority: the importer selects the immutable capsule from the current plan-bound receipt, validates its complete object closure, and derives the destination pointer. A missing, stale, or invalid supplied pointer is recorded but cannot replace or invalidate an otherwise complete immutable contribution.

A schema-4 capsule binds the test ID, target, definition hash, full effective-input map, exact Factorio installation and resolved mod closure when applicable, trust-class-validated producer identity, exit code, structured `mir-test-result-v1`, assertion outcomes, artifact hashes, stdout and stderr hashes, timestamps, duration, and result digest. `passed.json` is only an atomic pointer to an immutable attempt capsule. Corrupt pointers are quarantined. A changed definition, verifier, policy, binary, mod archive, candidate, or other effective input creates a different fingerprint instead of rewriting history.

## Worker And Aggregate Gate

Run one planned test with:

```powershell
./tools/mir.ps1 verify run-one --target 2.1 --plan out/verification-plan.json --test <stable-id> --fingerprint <sha256> --factorio <factorio.exe>
```

The worker rechecks the exact evidence before execution. If a matching worker is active, it waits and adopts the completed pass. Otherwise it writes `running.json`, executes the command, writes the attempt and pass or block capsule, and clears the marker.

Evaluate the complete plan with:

```powershell
./tools/mir.ps1 verify gate --target 2.1 --plan out/verification-plan.json --output artifacts/assurance/evidence-bundle.json
```

Every worker and the gate reconstruct the canonical schema-4 plan from the named profile and current authorities, reject missing, extra, duplicate, stale, or altered test entries, and compare the immutable plan-material digest. The gate recomputes the candidate domain manifest when runtime scenarios are present and requires trusted exact passing evidence for every planned fingerprint. Each forced test records its minimum completion time, run ID, and run attempt rather than inheriting plan-wide freshness only.

## CI

The default workflow is named `MIR`; its aggregate required check is `MIR / verification-gate`. When every fast-profile fingerprint is already present as trusted reusable evidence, the workflow schedules one explicit reuse-only no-op row because GitHub rejects an empty dynamic matrix. That row runs no repository test and produces no capsule; the aggregate gate still validates every planned fingerprint from the restored ledger.

Fast, targeted, and scheduled matrix workers upload only their exact `test-id/fingerprint` subtree. Every completed worker attempt, including a failed attempt, also writes `worker-receipts/<plan-material-sha256>.json`. Receipt schema 2 binds the semantic plan and required-test-set digests, plan generation/source/target/profile, plan coordination producer, exact work row and freshness policy, contribution-preparation workflow/run/attempt/job identity, evidence producer and trust, completion state, immutable capsule hash, and result digest. The aggregate job downloads each GitHub artifact into its own artifact-name directory and invokes the plan-bound importer. The importer admits only the artifact selected by each scheduled work row, validates the receipt, capsule, structured result, stdout/stderr, and every declared artifact digest, copies only selected immutable files without overwriting different bytes, preserves failed capsules behind a derived blocking pointer, and derives passing pointers deterministically. Missing and failed rows do not stop later successful imports, duplicate exact-row contributions are release-blocking, irrelevant stale artifacts are reported and ignored, and the summary remains available even when proof closure fails. Whole-ledger artifact merging and `merge-multiple: true` are forbidden because creation or extraction order must never select evidence.

Worker ingestion rejects absolute or traversing paths, mixed-slash traversal, NTFS alternate data streams, Windows device names, symlinks and reparse points, duplicate case-folded or Unicode-normalized paths, and immutable-object collisions. `.mir/assurance.json` also caps artifact count, per-artifact entries, total expanded bytes, and individual file size. Generated scenario summaries remain outputs under `.work/`; repository input enumeration excludes `.work/artifacts`, `.work/build`, and `.work/output`, while the receipt and capsule bind the resulting summary digest.

The protected full workflow remains a separate content-addressed-object path. It enforces the execution DAG `F0 -> F1 -> F2 -> F3 -> F4 -> gate -> seal`; its plan is always fresh, uploads only the exact planned candidate, verification context, and candidate descriptor, and never transfers historical distribution archives. Each worker starts without the shared ledger and uploads content-addressed evidence objects plus non-authoritative raw outputs. The gate downloads every contribution into an isolated artifact directory, imports only canonical JSON objects whose filename and bytes match the SHA-256 address, rebuilds its evidence index from those accepted objects, evaluates the plan, writes the evidence bundle, and saves one updated immutable cache key. Mutable indexes, leases, raw outputs, artifact listing order, and completion order cannot choose the aggregate result.

Runtime, targeted, full, and scheduled workflows use trusted self-hosted Windows runners. They build one candidate, upload the same bytes to every worker, and never use `pull_request_target`. Self-hosted Factorio binaries, local proprietary mods, publishing credentials, and untrusted fork code must remain isolated.

## Qualification And Sealing

### Candidate reservation and assignment

A planned release reserves a `candidate_floor` but has `candidate_id: not-assigned`. A reservation is sequencing policy, not evidence and not a package identity. At source freeze, assign the first exact candidate ID at or above that floor and bind it to the frozen source commit, tree, and package-source digest in the ReleaseRecord and append-only transition record. Any later package-visible source change invalidates that candidate and requires a new candidate ID; never rewrite an existing candidate's source or archive identity. Generated views must show reservation and exact candidate identity separately.

Verification planning is valid before candidate assignment, but scenario-domain plans still require exact archive bytes. In the `planned` state, the fast workflow deterministically builds one development archive and transfers those same bytes with the plan; the plan binds its `package_source_commit` field to the current source snapshot for command reconstruction and fingerprinting, while the typed release record remains package-empty and `authority_class` remains a non-candidate planned reservation. Development-archive evidence is useful for integration and regression feedback but cannot qualify or seal a release. Source-frozen planning binds the recorded package-source commit. Candidate sealing, seal verification, promotion, and every exact-candidate assertion continue to use strict candidate authority and reject `not-assigned`, a reserved floor, missing package identity, or an unfrozen archive.

For MIR 3.2.0:

```powershell
./tools/mir.ps1 assurance build --target 2.1
./tools/mir.ps1 verify plan --target 2.1 --profile full --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip' --output out/verification-plan.json
./tools/mir.ps1 verify run --target 2.1 --plan out/verification-plan.json --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip'
./tools/mir.ps1 verify gate --target 2.1 --plan out/verification-plan.json --output artifacts/assurance/3.2.0-assurance-qualification.json
```

The canonical full and backport profiles cannot pass F4 until all of these release authorities bind the exact candidate:

- `release.approved-delta` checks both archive and package-content hashes plus package source authority;
- `runtime.performance-regression` produces a fresh paired qualified-baseline campaign in `.mir/evidence/<version>-performance-regression.json` and immediately checks it;
- `manual.release-review` checks the package-focused attestation in `.mir/evidence/<version>-manual-review-attestation.json`.

Schema-3 performance evidence must bind the exact prior release, candidate, source commit, Factorio binary, machine, mod closure, settings, scenarios, and harness. It uses at least one warm-up and five balanced measured pairs. Every governed lane must meet the 20 percent median ceiling or its small absolute-noise allowance, and any declared absolute ceiling. It also preserves maximum-observed compiler artifact-volume counters plus the telemetry fingerprint for every measured diagnostics-off and diagnostics-on candidate run, so timing changes can be separated from plan, coverage, context-copy, closure-cache, and sanitation volume.

The full and backport no-reuse plans create and validate that evidence as one capsule. For a focused preflight, run the same composed producer/verifier:

```powershell
.\scripts\Invoke-MIRPerformanceQualification.ps1 `
  -Candidate artifacts\candidate\more-infinite-research_3.2.0.zip `
  -PriorRelease dist\more-infinite-research_3.1.9.zip `
  -FactorioBin C:\Factorio-2.1.11\bin\x64\factorio.exe `
  -LocalModZipDir C:\Factorio-mods-2.1 `
  -ExpectedSourceCommit (git rev-parse HEAD) `
  -ExpectedBaselineVersion 3.1.9 `
  -ExpectedFactorioVersion 2.1.11
```

The generated evidence path is an output, not a verification-plan input. This prevents a no-reuse plan from validating stale evidence or invalidating its own fingerprint while it writes the fresh campaign.

The campaign uses the non-shipped `fixtures/performance-regression-probe` symmetrically for exact-archive diagnostics-off phase timing. The probe does not enter either release ZIP. Medium and large ecosystem lanes remain load observations over their exact resolved closures. Candidate ecosystem rows must also satisfy the current sanitation claim gate. The sealed prior-release baseline must pass its Factorio process, timeout, dependency, and closure checks, but is not required to emit a sanitation ledger introduced by the candidate.

The manual attestation must be schema 2, passed, self-hashed, tied to the exact candidate bytes, package-content hash, immutable package-source commit, and qualified Factorio binary, and contain reviewer, time, notes, and portable hashed artifacts for every package checklist item. The package-source commit must be an ancestor of the qualification commit and package-visible roots must remain identical; binding the attestation to the package source avoids the impossible requirement for a committed attestation to predict its containing commit. After reviewing and committing the exact candidate and qualification record, create and verify the seal:

`runtime.upgrade` is one F4 matrix result with five mandatory, independently hashed rows: base/default, Space Age native owner, automatic family creation, base continuation, and mod-set configuration change. The configuration-change row removes its source-only compatibility fixture before loading the candidate and proves current research, fractional progress, generated lifecycle state, and removal of only the dangling recipe target.

Ecosystem evidence is candidate-bound: the release-targeted gate must pass the exact candidate ZIP through every local repair and representative scenario and must not rebuild distribution bytes during verification. The composed `runtime.ecosystem` lane skips the release-gate clean-tree check because source authority is independently enforced by approved-delta, manual-attestation, and protected sealing gates. Ecosystem evidence is also bounded by `.mir/sanitation-budgets.json`. Manifest scenarios resolve through the `campaigns` scope, while target-qualified release repair smokes resolve through `local_mod_zips`. A scenario passes only when its observed external prunes exactly include every reviewed prune and contain no more than the declared maximum unreviewed prunes. Release budgets use zero; a missing budget or mismatch is `REVIEW_REQUIRED`, never a compatibility pass.

```powershell
./tools/mir.ps1 assurance seal --target 2.1 --factorio 'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe' --prior '.\dist\more-infinite-research_3.1.9.zip' --plan out/verification-plan.json
./tools/mir.ps1 assurance check-seal --seal .mir/evidence/candidate-seals/mir-3.2.0-factorio-2.1.json
```

Seal schema 4 records the candidate ID, immutable package-source commit and material hash, and later qualification-source commit and tree separately. The legacy `source_commit` and `source_tree` fields remain qualification-source aliases for evidence compatibility. A clean candidate uses `git-commit-normalized-package-v1`, binding the exact source tree and package file count while deriving the normalized package-source hash directly from committed package files. A historical candidate whose material hash was captured from a dirty precommit worktree uses `git-index-with-captured-worktree-v1`; its descriptor records each affected path, eventual Git blob, and captured worktree hash. The two explicit variants preserve clean commit authority without pretending that checkout newline conversion can recover older mixed index/worktree bytes.

Seal creation requires the package-source commit to be an ancestor of qualification, proves that package roots are unchanged, re-evaluates the recorded package material identity against identical Git blobs at both commits, and deterministically reconstructs the exact archive and content identities from narrow committed-source archives at both commits. This allows assurance, evidence, and release-governance commits to qualify frozen candidate bytes without misrepresenting them as package source.

`candidate_content_sha256` and `package_source_sha256` use the same canonical package identity: the ZIP's versioned root directory is removed, text line endings are normalized to LF, entries are ordered by package-relative path, and each row binds normalized length plus SHA-256. Plans, domain manifests, build receipts, performance evidence, manual attestations, release authority, and seals must use this identity; the raw archive SHA-256 separately binds compression and complete ZIP bytes.

Schema 4 also binds the performance-evidence and manual-attestation paths, file hashes, and passed statuses. `check-seal` independently repeats the source ancestry, package-root, material-identity, and two-commit reconstruction checks alongside the candidate, plan, bundle, verifier, producer, and other repository identities. Promotion checks cannot tag, push, create a GitHub release, or upload to the Mod Portal.

## Backports

Backports recalculate every fingerprint on the target branch. MIR 2.5.0 uses the Factorio 2.0 candidate ZIP, Factorio 2.0 verification profile and binary, target scenario declarations, target fixtures and mod lock, target dependency contract, and exact MIR 2.4.9 prior release. Factorio 2.1 evidence cannot satisfy the Factorio 2.0 aggregate gate even if source files look similar.

Tooling may be ported as one portable change, but target metadata, API adapters, reduced feature decisions, fixtures, archive bytes, and evidence remain target-local. Build the target candidate before planning any matrix that requires package domains.

## Adding Tests Or Domains

Add a permanent test or matrix template to `validation/tests.yml`, declare every effective input, and route it through the appropriate `.mir/assurance.json` change classes. Add package-domain rules or scenario dependencies to `validation/domains.yml`; unmatched package paths must remain conservative. Update `Test-MIRAssurance.ps1`, `.mir/fixtures.yml`, `.mir/modules.yml`, this document, and any affected target profile when the verification contract changes.

## Human Gate Boundary

The pre-seal package review covers technology-tree layout, icons, locale fit and truncation, settings UX, save UI, and human balance judgment. It is a required F4 input and must be attested against the exact package candidate.

GitHub release text, Mod Portal presentation, screenshots, links, and final public claims are a separate pre-publication review. They do not block creation of a sealed package candidate, but publication must not proceed while they remain pending. Any compatibility campaign without honest automation also remains manual and cannot be converted into a support claim by the package attestation.
