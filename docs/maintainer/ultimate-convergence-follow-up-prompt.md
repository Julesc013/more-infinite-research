---
title: "Ultimate Convergence Follow-Up Audit Prompt"
status: current
applies_to: "3.2.5, 2.5.x, 3.3.x, 2.6.x"
audience: maintainer
doc_type: how-to
owner: mir-maintainers
last_reviewed: 2026-08-05
supersedes: []
superseded_by: []
---

# Ultimate Convergence Follow-Up Audit Prompt

Use the following prompt with the worker completing the concurrent repository/control-plane refactor. It asks for a read-first completeness check against the convergence audit and explicitly prevents unsupported closure claims.

## Copy/paste prompt

```text
You are following up on the MIR 3.2.5 → conditional 2.5.5 → 3.3.x → 2.6.x convergence programme after another worker completed repository and Control Plane changes.

The authoring baseline was synchronized `dev` merge `92e82a75492ac717275a11f187e59e54051f7ffc` from pull request 44. Its package-excluded Phase A checks were green, but that fact does not close P11, assign C32, qualify 3.2.5, authorize 2.5.5, or open 3.3. Treat the current repository as authoritative if it has advanced.

Work safely in the current repository. Other work may still be present. Do not stash, reset, clean, overwrite, or stage unrelated changes. Begin with a read-only audit of the current committed and working-tree state. Identify which findings are already satisfied by exact code, schemas, records, tests, or evidence and which remain open. Do not infer implementation from documentation and do not infer qualification from startup success.

Required reading:

- AGENTS.md
- .mir/docs.yml
- .mir/modules.yml
- .mir/compatibility.yml
- .mir/streams.yml
- .mir/fixtures.yml
- .mir/branches.yml
- docs/maintainer/documentation-governance.md
- docs/architecture/module-boundaries.md
- docs/compatibility/claim-levels.md
- docs/reference/schemas/stream-spec.md
- docs/maintainer/fixture-workflow.md
- docs/maintainer/backporting.md
- docs/releases/ultimate-convergence-audit-action-register.md
- docs/releases/3.2.5-to-2.6-convergence-programme.md
- docs/releases/3.2.5-convergence-release.md
- docs/architecture/3.3-2.6-convergence-platform-roadmap.md
- docs/architecture/mir-extension-protocol-v1.md
- todo.md

First report the exact HEAD, upstream relation, dirty paths, current release pointer, release states, and any concurrent-worker overlap. Then check every item below.

1. Runtime research-cost transitions

- Inspect prototypes/mir/runtime/productivity_family_adoption.lua and the data-stage adoption payload.
- Confirm progress preservation uses old_fraction × old_cost / new_cost.
- Confirm runtime consumes versioned old/new cost descriptors rather than expanding string parsing.
- Confirm fixed, linear, exponential, and hybrid form a complete 16-row transition matrix.
- Confirm current research, exact level, fractional progress, queue, completed levels, configuration change, save/reload, second reload, and continuous-versus-reload equivalence are covered.
- Confirm unknown descriptors fail closed with a stable diagnostic.
- Check INC-2026-0054 and CHG-2026-0007; do not close either without matching proof.

2. Formula and identity safety

- Confirm semantic_digest excludes provenance and authority_digest includes it.
- Confirm qualification identity binds target, exact environment, observations, evaluator ABIs, and proof closure outside the semantic model.
- Confirm positivity and monotonicity rely on algebraic parameter proof, with numeric envelope and sampled vectors as separate layers.
- Confirm explicit limits for formula length, tokens, parse depth, AST nodes, exponent magnitude, supported level, and finite evaluated cost.
- Confirm over-budget or unknown external formulas are preserved or refused safely.

3. Semantic-domain referential integrity

- Confirm product.balance exists in the semantic-domain catalog.
- Validate every task read/write domain, ownership write, downstream domain, and obligation-alias source/target.
- Confirm every domain has one owner or an explicit composition rule.
- Confirm unknown paths select conservatively and fail governance.
- Check CHG-2026-0008.

4. Ownership specificity

- Confirm one most-specific source-path ownership rule wins.
- Confirm equal specificity fails unless composition is explicit.
- Confirm broad scripts/**, validation/**, and .mir/** rules are fallback-only and do not silently add ownership beside a specific rule.
- Add negative tests for ambiguous equal-specificity matches and broad-fallback overlap.

5. Logical path authority

- Confirm durable records store logical path IDs rather than independently embedding legacy and canonical physical paths.
- Confirm exactly one resolver maps logical IDs to physical paths.
- Confirm migration is dual-read/single-write, includes parity receipts, and has declared alias sunsets.
- Search Control Plane policies, tasks, schemas, generated views, workflows, and release records for hard-coded duplicate path authority.
- Check CHG-2026-0009.

6. Candidate reservation

- Confirm planned 3.2.5 records `candidate_floor: C32` separately from `candidate_id: not-assigned`, and generated views describe the former only as a reserved floor.
- Confirm candidate_id remains unassigned until source-frozen or package-built.
- Confirm observations, performance, attestations, and proof cannot bind a reservation.
- Confirm C32 is built once after all package-visible work; later package change becomes C33.
- Check CHG-2026-0010.

7. Append-only release governance

- Confirm published identity is immutable.
- Confirm later qualification, incident, and transition facts are append-only records/events.
- Confirm generated views calculate current status without rewriting history.
- Confirm remaining obligations do not make historical publication facts appear mutable.
- Check CHG-2026-0010.

8. P11 closure

- Inspect the exact 2.5.0 release identity, protected retry, retained observations, performance binding, BZ result, and stabilization record.
- Separate valid observations from invalid evaluation, transport, aggregation, or custody.
- Do not claim P11 closure without exact post-publication proof or an independently qualified P12.
- Do not create 2.5.1 for tooling-only or assurance-only changes.
- Check CHG-2026-0011.

9. Bounded 3.2.5 product

- Confirm one derived terminal outcome per leaf subject and no competing selection authority.
- Confirm load, integrity, semantic, progression, upgrade, configuration-change, recovery, interactive, and performance dimensions are independent.
- Confirm EcosystemProfile, ExactEnvironmentLock, and ProofAssertion remain distinct.
- Confirm support output is deterministic, localized, privacy-safe, bounded, and explicit about truncation.
- Confirm report failure cannot alter compilation.
- Confirm Base, Space Age, and P11/BZ are first proof profiles.
- Confirm broad MEP, FeatureManifest/SettingSpec conversion, ProcessIR, economy solving, and universal target generation remain outside 3.2.5.
- Check CHG-2026-0005.

10. MIR 2.5.5 feasibility

- Confirm a ProjectionFeasibilityRecord precedes any 2.5.5 release candidate.
- Confirm every 3.2.5 slice has a Factorio 2.0 disposition.
- Confirm no second compiler or duplicate policy authority is needed.
- Confirm support/report transport remains useful on 2.0.
- Confirm deterministic tree and package reconstruction and independent target proof.
- Preserve a failed feasibility report; do not fake a release.
- Check CHG-2026-0015.

11. MIR 3.3 authority graph and mutation

- Confirm current authorities evolve rather than creating parallel writable WorldIR/PolicyIR/PlanIR/Lua EvidenceIR objects.
- Confirm the desired semantic product DAG is acyclic.
- Confirm FeatureManifest is an aggregate index over independently owned fragments.
- Confirm SafetyKernel is physically non-overridable and PolicyEngine chooses only legal outcomes.
- Confirm field-specific merge laws declare and test algebraic properties.
- Confirm every prototype write is a planned operation executed only by stage executors.
- Confirm settings, prototype, runtime, migration, target, and publication use specialized plans/executors.
- Confirm CompilerContext is explicit through pure code and CompilationRun references immutable artifacts by digest.
- Confirm runtime features have state schemas, one forward migration path, idempotent reconciliation, reload equivalence, and removal behavior.
- Check CHG-2026-0012.

12. MEP-1 boundary

- Confirm protocol semantics are transport-independent.
- Confirm unique mod-data discovery on 2.1 and a frozen stage-local bus on 2.0.
- Confirm registration deadlines and finalizer-order requirements are separate.
- Confirm stable 3.3.0 surface is limited to CompatibilityFragment, ProfileFragment, ProofFragment, PresentationFragment, capability negotiation, and dependency/conflict declarations.
- Treat declarative providers, static settings, runtime descriptors, and TrustedAdapterV1 as experimental/deferred until separately qualified.
- Confirm no extension can override hard safety or confer official support.
- Confirm differently named forks need an explicit runtime-storage migration bridge.
- Check CHG-2026-0006.

13. Settings and ProcessIR

- Confirm typed setting values and ordered override provenance are planned.
- Confirm dynamic instances cannot create startup settings after settings freeze.
- Confirm ProcessIR derives from canonical recipe facts rather than rescanning prototypes.
- Confirm positive-yield-loop certification precedes broad complex-overhaul productivity.
- Check CHG-2026-0014.

14. Assurance and CI

- Confirm Control Plane v5 is evolved, not rewritten.
- Confirm CaptureKey, CompilationKey, RealizationKey, and EvaluationKey are distinct.
- Confirm observations are Merkle-sliced and assertions name only the slices they read.
- Confirm environment batching excludes upgrades with distinct transitions, settings differences, fault injection, performance, clean-process proof, and configuration-change mod-set differences.
- Confirm freshness classes and the final protected no-reuse gate.
- Confirm scheduling optimizes execution but never omits proof.
- Confirm external-mod runner, protected aggregator, and publisher roles are isolated.
- Check CHG-2026-0013.

15. True target projection

- Confirm exact 2.6 is generated from immutable 3.3 semantics, latest qualified 2.5.x baseline, capability certificate, semantic target policy, reviewed adapters, and release overlay.
- Confirm adapter round-trip where meaningful, unowned-field preservation, idempotence, locality, and semantic parity.
- Confirm reconstruction does not depend on a pre-existing projection branch.
- Confirm the dual-parent commit is provenance rather than the sole producer.
- Check CHG-2026-0015.

16. Non-negotiable zero budgets

Check and report exact enforcement for direct prototype writes outside executors, global context reads in pure code, unversioned schemas, unnamespaced extension IDs, late settings, safety overrides, unclassified target/package paths, undeclared domains, ambiguous owners, undeclared writes, broken adapter laws, unmigrated runtime state, stale claims, revoked sealed proof, impact false negatives, unique temporary-branch logic, post-seal rebuilds, and lost completed observations.

17. Release-train execution completeness

- Reconcile `325-A1a`, every `325-A0` through `325-D4` row, and the first complete `325-B0` slice in the canonical convergence programme with code, records, tests, and evidence.
- Confirm fast, targeted, and scheduled worker evidence is downloaded into isolated artifact directories, every worker carries an immutable receipt for the exact plan/source/work/trust/capsule/result context, only plan-selected test/fingerprint objects are imported, every pointer/capsule/result/log/artifact digest is validated, and artifact order cannot select a stale restored pointer. Confirm protected Control Plane v5 retains immutable-object aggregation and exact aggregate validation.
- Confirm the latest exact PR head, not an earlier same-head run, closes `325-A1a` before merge or release-state work proceeds.
- Confirm the complete 3.2.5 freeze packet can be materialized before assigning a candidate.
- Confirm the freeze defect register closes algebraic cost proof, numeric envelope, owner removal/transfer, descriptor authority semantics, README reset wording, exact default parity, save/reload/second reload, and Factorio 2.0 cost disposition.
- Confirm the declared minimum product independently covers Factorio 2.1 Base/Space Age and, only after feasibility passes, Factorio 2.0 Base/Space Age.
- Confirm the bounded mandatory ecosystem matrix locks exact versions/hashes, claim levels, fixtures or named load-checks, budgets, and terminal wording for Base, Space Age, P11/BZ, one owner pack, one broad overhaul, and one negative/conflict row.
- Confirm `325-B0` traces one research-cost proposition through compiler semantics, terminal disposition, typed proof, bounded support output, and Factorio 2.0 projection before compatibility breadth expands.
- Confirm every release state is admitted separately and publication consumes sealed bytes without rebuilding.
- Confirm `255-F0` feasibility precedes every 2.5.5 branch, release record, or candidate action.
- Confirm a passed 2.5.5 feasibility result produces new source-lock, portable-delta, backport-manifest, reconstruction, target-proof, seal, and public-byte records rather than mutating the 2.5.0 authorities.
- Confirm a failed feasibility result is preserved as `deferred-with-evidence` and becomes a 3.3/2.6 design input.
- Confirm the 3.3 M0 handoff packet contains exact publicly verified modern and latest-target baselines, or an exact 2.5.5 deferral, before any behavior-preserving platform cutover begins.
- Report which work can proceed in parallel and the exact barrier at which it must join the critical path.

For each item, return:

| Finding | Status | Exact evidence | Remaining gap | Owner/record | Required validation |

Allowed status values are implemented-and-proven, implemented-unqualified, partially-implemented, planned-only, contradicted, blocked-external, and not-applicable-with-proof.

Do not edit records merely to make views green. Do not mutate prototypes from compatibility policy. Do not create or upgrade a public compatibility claim without fixture or named load-check evidence. Before running tests, materialize the MIR verification plan, inspect its exact fingerprint and selected closure, reuse only trusted matching evidence, and do not start duplicate workers. Run the narrowest required checks first.

End with:

1. exact findings the previous worker missed;
2. exact findings already handled;
3. any conflicts between current code, docs, manifests, and generated views;
4. a minimal ordered follow-up patch plan;
5. actions intentionally not taken because they require package proof, protected execution, external evidence, or maintainer authority.
```

## Expected use

The receiving worker should use the prompt after its current isolated refactor reaches a clean commit boundary. Its first response should be an evidence-backed audit, not an assertion that all work is complete. Implementation should remain split by package visibility and proof requirements.
