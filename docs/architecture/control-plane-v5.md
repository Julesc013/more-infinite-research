---
title: "MIR Control Plane v5"
status: current
applies_to: "post-3.2.2"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-31
supersedes: []
superseded_by: []
---

# MIR Control Plane v5

Control Plane v5 is a tooling-only fixed point after immutable MIR 3.2.2. It does not authorize player-visible changes to C24 or the frozen 2.5-P9 projection.

## Authority

Humans edit typed records under `.mir/changes/`, `.mir/incidents/`, `.mir/tasks/`, `.mir/releases/`, and `.mir/release-transitions/`. The current-role pointer is `.mir/releases/current.json`. Release ledgers, TODOs, candidate documents, dashboards, branch status, publication checklists, backport queues, and release-note identity blocks are generated views.

Every release follows the ordered state machine:

```text
planned
→ source-frozen
→ package-built
→ focused-qualified
→ candidate-qualified
→ manually-accepted
→ protected-qualified
→ sealed
→ promoted
→ tagged
→ published
→ publicly-verified
```

Transitions require immutable proof objects. A historical release imported with an explicit assurance exception may calibrate v5 but cannot satisfy a future release gate.

## Package freeze

`.mir/control-plane/package-locks.json` binds C24 and P9 package-source, content, archive, size, and entry identities. Every v5 commit must pass the package-freeze gate. Tooling, manifests, generated views, and evidence indexes may change; package roots may not.

## Task graph

Task records declare prerequisites, semantic domains, effective inputs, outputs, resources, freshness, side effects, retry policy, and completion proof. F0 through F4 remain classification labels only. Scheduling follows prerequisites and resource constraints.

Aggregate nodes read child results and never execute child commands. `static.full` remains a v4 shadow input during migration but is not an executing v5 task.

The atomic catalog separates documentation, generated views, architecture boundaries, module dependencies, compiler schema, compiler contracts, settings, locales, release authority, backport authority, verification schemas, PowerShell quality, scenario declarations, observation/evaluation replay, immutable context materialization, content-addressed evidence, execution, CI workflow, package identity, package composition, deterministic construction, upgrade, ecosystem, approved delta, performance, manual acceptance, protected qualification, seal, reconstruction, promotion, tag, publication, public-byte verification, and control-plane records. Commands are argument arrays rather than shell strings.

Task activation is explicit. Verification calibration selects only verification nodes. Release and publication plans select their own nodes and close prerequisites across earlier stages; target-specific nodes such as dual-parent reconstruction apply only to Factorio 2.0. This prevents qualification from accidentally performing tag or publication actions while keeping the complete release proof chain in one typed DAG.

`scripts/Invoke-MIRControlPlane.ps1 plan` supports `changed`, `qualify-incremental`, `calibrate-fresh`, and `rerun-failure` modes. Every selected row includes its semantic impact reason, freshness class, resource class, prerequisites, and effective-input digest. Unknown paths select the complete graph and fail governance until ownership is added.

An effective-input digest contains canonical content identities for every repository file matched by the TaskNode declaration, plus the governed candidate and package-source identities for virtual inputs. `source:` inputs are resolved from the immutable package-source checkout and include its exact commit; unqualified inputs resolve from the v5 control-plane checkout. Source-scoped commands execute with the immutable source as their working repository. Runtime adapters bind both exact product inputs and the current executor implementation. Runtime-only inputs such as a Factorio installation, prior archive, or mod closure are explicitly marked worker-resolved; they cannot silently masquerade as repository content.

For a new candidate with no exact prior qualification bundle, context materialization requires `-FactorioBin`. The materializer resolves that executable, requires its product version to equal the target profile's qualification version, hashes its binary and complete official-data tree, and writes only the portable composite identity into the immutable environment lock. A zero-lock executable context is rejected before staging. Existing exact candidate-qualification locks may supplement the explicitly selected identity, but they cannot replace the explicit seed for a new candidate. The ABI-3 composite excludes the absolute installation root; imported v4 path-bound composites are accepted only as backward-compatible matching aliases when the independently bound binary and official-data identities also agree.

Every native Factorio worker resolves the selected executable before launch and compares its composite installation digest, binary digest, byte length, product version, and official-data tree digest with the immutable environment locks in the verification context. The first native operation in an executor process hashes the complete installation; later operations in that same process may reuse only that process-local result under the exact binary path, byte length, and modification-time key. Independent worker processes therefore perform independent full scans. No runtime, upgrade, ecosystem, approved-delta, or performance observation may be emitted from an installation that fails the comparison.

Target-line profiles own stable engine and runner policy. Release records may additionally own the exact save-upgrade baseline, target version, and fixture. Context materialization validates that the baseline is a typed release on the same Factorio target, that the target version equals the candidate release, and that the named fixture exists; it then projects this release-specific authority into 	arget-profile.json and binds those exact staged bytes in nvironment-locks.json. This keeps C24 calibration on 3.2.1 to 3.2.2 while C30 qualification uses only 3.2.2 to 3.2.3.

## Observation and evaluation

Factorio work produces canonical observations. Pure evaluators consume observation objects plus versioned assertion records. Capture, compilation, realization, and evaluation identities are independent, allowing assertion, parser, diagnostic, and presentation changes to reuse sound engine observations.

Approved-delta capture follows the same separation. For the C24 hotfix, the executor independently hashes every file entry in the exact C21 baseline and C24 candidate archives, records archive/content/byte/entry/source identities, and then applies `c24-four-path-hotfix-v1` from `.mir/control-plane/approved-delta-policies.json` as a pure set comparison. The policy permits only `prototypes/mir/runtime/planet_discovery_recovery.lua` to be added, no removals, and changes to `changelog.txt`, `info.json`, and `prototypes/mir/runtime/scripted_techs.lua`. This native path supersedes the calibration use of the historical C22-bound patch artifact; that artifact remains historical input and cannot stand in for fresh C24 evidence. C30 uses the same native evaluator with `c30-platform-logistics-hotfix-v1`: exact tagged 3.2.2 versus frozen C30, one added compiler-index file, no removals, and 67 exact changed paths. The complete allowed set is package-identity-bound rather than inferred from filenames during admission.

Compatible scenarios share an exact environment signature. Performance, transition, destructive fault-injection, distinct-setting, distinct-closure, source-save, and clean-process proofs remain isolated.

`validation/generated/execution-registry.json` is generated by parsing the validation runner with the PowerShell AST. For target 2.1 it covers all 116 declarations and 117 assertions. Exactly 87 declarations have one statically resolved literal runner authority; 29 conditional, duplicated, or dynamic declarations use a named isolated fallback. The registry produces 116 exact-environment batches, including 113 Factorio-backed processes for 114 Factorio-backed assertions. This deliberately small reuse result is the sound result for the current runner: no launch is saved by merging merely similar fixture declarations.

The historical adapter converts each of the 130 schema-4 v4 evidence rows for C24 into a canonical `legacy-v4-adapter` observation. A versioned `status-equals` assertion then runs through the same pure evaluator used for native v5 captures. `.mir/control-plane/baselines/3.2.2-v5-replay.json` records independent capture, observation, evaluation, and evidence digests for every row; it is deterministic and contains no wall-clock identity material.

## Impact, freshness, and reruns

The planner maps changed paths to owning modules and domains, closes downstream reads, and selects proof obligations. Unknown ownership broadens selection and emits a governance failure. Mutation calibration protects the zero-false-negative invariant.

Freshness is proposition-specific: content-eternal, environment-bound, candidate-bound, transition-bound, protected-release-fresh, or always-fresh. Failure-directed reruns select the failed node, invalidated prerequisites, changed downstream inputs, and remaining release-fresh obligations.

`.mir/control-plane/mutation-calibration.json` deliberately mutates provider, setting, locale, release-record, control-plane, and unknown inputs. The control-plane gate requires every necessary task to remain selected and fixes the false-negative budget at zero.

## Verification context and evidence

Planning emits one immutable verification-context bundle. Workers verify its digest and do not rediscover candidate, target, transition, scenarios, closures, or policy.

Each context directory is named by a digest over ten exact members: plan, candidate descriptor, release transition, expanded tasks, expanded scenarios, package-domain manifest, target profile, environment locks, control-plane lock, and `candidate.zip`. A manifest binds every member's byte length and SHA-256; `context-digest.txt` repeats the reconstructed context identity. Existing contexts are validated and reused byte-for-byte, never overwritten. Executable context ABI 3 additionally locks the controller commit, tracked-worktree diff identity, absence of untracked governed files, every control-plane implementation file, and at least one target-version-matching Factorio installation identity. An executor refuses ABI 1/2 contexts, zero-lock contexts, and any context whose controller inputs drift after materialization. Fresh-calibration proof further requires that the locked controller checkout was clean and committed.

Evidence is stored by SHA-256 under `artifacts/evidence/objects/sha256/`. Indexes and leases are rebuildable coordination data. Revocation may target a producer ABI, evaluator ABI, canonicalization ABI, digest set, or time range without discarding unrelated observations.

The evidence object's address is the SHA-256 of its canonical UTF-8 bytes. Rebuilding the index verifies filename/address parity, parses every object, applies `.mir/control-plane/evidence-revocations.json`, and can explicitly move malformed objects into quarantine. Exact unrevoked passing evidence yields `REUSE`; absent evidence yields `RUN`; stale, revoked, or invalid matches yield `INVALID` with a required `RUN` follow-up. Fresh calibration still forces `RUN`. Process and CI-job leases are mutable, expiring coordination only; a matching active lease is adopted and never counted as passing evidence.

`.github/workflows/control-plane-v5.yml` is the executable CI DAG. Its protected self-hosted context job builds the exact locked source archive and seeds ABI 3 with the selected trusted Factorio installation; a hosted runner cannot invent or omit that lock. Static and package task sets then run independently in topological order. Protected self-hosted workers capture one Factorio process per exact environment signature, upgrade and approved-delta transitions, the governed ecosystem closure, and the isolated paired performance campaign. Each native adapter writes an immutable observation and evaluates it through a pure assertion before producing TaskNode evidence. A separate job admits only a maintainer-authored attestation for the exact archive, content, and package-source identities. Every worker uploads content-addressed objects. The sole final status, `MIR / verification-gate`, runs inside the protected runner environment, reconstructs the index, and requires exact passing objects for every planned executable TaskNode and every Factorio-backed environment batch; job status alone is never accepted.

Package workers receive both the immutable context and a checkout at the descriptor's exact source commit. Identity and composition compare source roots, content identity, archive bytes, and the complete entry set. Determinism builds that exact checkout twice and requires both outputs to be byte-identical to `context/candidate.zip`.

`candidate.zip` is the context member name, not a valid Factorio mod filename. Before any native runtime, upgrade, ecosystem, approved-delta, or performance adapter launches, the executor reads the candidate's root `info.json`, validates its safe name and exact release version, copies the context member to a context-addressed staging directory as `<name>_<version>.zip`, and rechecks the archive digest. Existing staged bytes are reused only when their digest is exact. This adapter changes no package byte and prevents Factorio's case-sensitive archive-name gate from confusing context storage identity with mod-loader identity.

## Acceptance

V5 toolchain admission requires agreement with v4 on candidate identity, required obligations, scenarios and environments, approved delta, upgrade, performance, manual result, aggregate verdict, and seal inputs for 3.2.2 and P9. The admission comparison requires complete historical outcome agreement for C24 and exact pending-verdict parity for each not-yet-performed P9 outcome. Admission also requires one complete fresh independent C24 calibration after verifier, impact, target-profile, or Factorio changes. P9 promotion has a separate operational-cutover comparison and cannot treat pending parity as release proof. Later releases are not fabricated as new v4 calibration baselines. A non-calibration release inherits only its target cutover: global and target state must be accepted, the exact fresh-calibration proof must be present, context-locked, digest-bound, unrevoked, and ABI-identical, and the current controller must descend from the calibrated implementation. Factorio 2.1 maps to C24; P9 remains the Factorio 2.0 calibration candidate and must complete its own operational proof. Full inherited admission additionally requires one exact protected qualification result and an exact-candidate protected seal.

`scripts/Invoke-MIRControlPlane.ps1 calibrate` executes the complete C24 `calibrate-fresh` plan, all process-required exact-environment batches, the specialized upgrade, ecosystem, approved-delta, and performance adapters, the exact historical C24 manual attestation check, and both result-only aggregates. A campaign uses one immutable context and one evidence root. `-Resume` adopts only one exact unrevoked passing object for the same context, identity, and `ci` trust class; duplicate objects fail closed. `calibration-proof` accepts only complete unambiguous TaskNode and environment closure, a qualification execution manifest, zero false-negative mutation calibration, exact package locks, and passing toolchain-admission shadow analysis. Its result is calibration authority only and is never a protected release seal.

Product semantics, fixtures, docs, and compatibility checks run from the immutable candidate source selected by the context. Release-history integrity is intentionally control-plane scoped: C24's package-source commit predates the final tag and distribution-inventory commits, so its own root `dist` set is not a valid post-tag release-history authority. The TaskNode instead binds the current `.mir/target-lines/**`, `.mir/distributions.json`, `dist/**`, and gate implementation. Candidate source and archive identities remain independently locked, so this scope separation cannot change candidate bytes.

Performance campaign authority is also intentionally controller scoped because C24's package-source commit predates the final C24 campaign row. Immutable files under `.mir/performance-campaigns/` are selected by exact release and candidate ID: C24 retains its C21 baseline for fresh v5 calibration, while C30 binds tagged 3.2.2 for candidate qualification. The selected file is included in the context control-plane lock. The executor verifies that it binds the context's exact candidate, baseline, target, and Factorio version, clones the immutable source into a context-addressed staging repository, and overlays that package-excluded authority file. Text-file identities are newline-normalized by the planner, so the executor also materializes the source-owned performance probe's final-fixes stage as deterministic UTF-8 without a BOM and with LF line endings; this prevents Git checkout conversion from changing Factorio's phase discovery while retaining the exact normalized source input. The executor additionally overlays the current controller's package-excluded compatibility audit so historical product checkouts receive release-engineering repairs without changing product source. An immutable overlay manifest binds all three files, their materialization rules, the resulting harness digest, and the unchanged package-source fingerprint. Compatibility audits resolve their requested output path early but materialize and revalidate the directory only immediately before governed artifact emission, avoiding a stale empty directory across multi-minute dependency resolution. Windows engine execution uses a fresh compact scratch root bound to the same immutable context and admits both exact-package and compatibility-audit runner paths only within a conservative 240-character budget; Factorio never receives the longer retained-evidence path as its mod root. After execution, the controller moves the complete raw artifact tree into the context-addressed evidence directory and verifies its context/strategy marker before admitting the measurement. The emitted schema-3 artifact must independently bind C21, C24, the source commit, the Factorio binary, the exact campaign lane set and run policy, the campaign and harness digests, and the third-party closure before v5 writes its observation, pure status evaluation, and TaskNode result.

The committed shadow baselines are deterministic projections of the immutable v4 verification plans, not mutable job state. The 3.2.2 baseline contains 17 non-scenario obligations and 113 scenario rows; its v5 plan contains the same coverage plus the three governed `package-build`, `runtime-state-contract`, and `static-validation` additions (116 scenarios total). The P9 baseline contains the same 17 obligations and 109 scenario rows, with the same three v5 additions (112 total). Every v4 environment row maps to exactly one AST-derived v5 scenario and one isolated process-required batch. The committed analysis records each v4 definition, scenario, and input digest beside the v5 environment signature, batch identity, and runner-authority digest, then binds the complete one-to-one mapping with a canonical digest.

The committed toolchain-admission analysis does not release P9. For 3.2.2, v4 and v5 agree exactly that no protected seal existed; that historical comparison passes admission analysis but remains permanently inadmissible as a future release seal. For P9, approved delta, upgrade, performance, manual acceptance, aggregate verdict, and seal inputs pass admission only as explicit `v4=pending` / `v5=pending` verdict pairs. Observed files outside the v5 evidence store are diagnostic input, not admitted proof. When `scripts/Test-MIRControlPlaneShadow.ps1` evaluates an immutable P9 context, it switches to operational-cutover mode and fails closed until every one of those dimensions is admitted through exact, unrevoked, context-bound v5 evidence.

Release-stage contexts contain verification prerequisites plus reconstruction, protected qualification, seal, final shadow cutover, and promotion nodes. Candidate descriptors keep the immutable package-source identity, while the context separately locks the exact qualification checkout. For P9 that checkout may be either the proven dual-parent integration commit and tree or a clean descendant whose complete package-source fingerprint remains exactly equal to the frozen P9 source fingerprint. The context records those roles as `dual-parent-integration` and `dual-parent-integration-successor`; any package-visible descendant is a new candidate and must not qualify as P9. This lets repository-governance and package-excluded fixture corrections run on the current target lineage while rebuilt ZIP bytes remain equal to the frozen package root. `aggregate` resolves a named aggregate subgraph without demanding later release actions or unrelated environment batches; `qualification` admits exactly `qualification.full` from a fresh protected execution manifest; `backport` admits the governed dual-reconstruction proof; `seal` binds candidate, context, plan, control-plane commit, component ABIs, and qualification manifest; and `promotion` requires exact seal and final shadow task objects. Protected evidence producers must match the governed repository, workflow, event, ref, environment, declared runner identity, actual self-hosted runner environment, trust-policy digest, context-locked control-plane commit, and current run attempt. Local callers and hosted runners cannot select the `protected-release` trust class successfully. A failed attempt may be retried without creating permanent evidence ambiguity because sealing and promotion select exact objects from the current protected run attempt.
