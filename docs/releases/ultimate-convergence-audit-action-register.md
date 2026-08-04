---
title: "MIR Ultimate Convergence Audit Action Register"
status: current
applies_to: "3.2.5, 2.5.x, 3.3.x, 2.6.x"
audience: maintainer
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by: []
---

# MIR Ultimate Convergence Audit Action Register

This register adopts the actionable findings from the 2026-08-04 ultimate convergence audit. It refines the [cross-release convergence programme](3.2.5-to-2.6-convergence-programme.md), the [3.2.5 release contract](3.2.5-convergence-release.md), the [3.3/2.6 platform roadmap](../architecture/3.3-2.6-convergence-platform-roadmap.md), and the [MEP-1 roadmap](../architecture/mir-extension-protocol-v1.md).

This is planning authority, not implementation evidence. It does not close P11, freeze C32, qualify a compatibility claim, change a published package, or authorize direct prototype mutation. Source inspection confirmed several defects and governance gaps; no new Factorio campaign was performed for this register.

## Governing release sequence

```text
close P11 post-publication assurance and BZ ambiguity
→ complete package-excluded authority migration
→ correct and complete the 3.2.5 research-cost transition slice
→ deliver the remaining bounded 3.2.5 vertical slices
→ freeze and build the first real C32 package exactly once
→ qualify, seal, publish, and publicly verify 3.2.5
→ decide 2.5.5 through a projection-feasibility record
→ freeze the qualified 3.2.5 and latest 2.5.x behavioral baselines
→ complete the 3.3 convergence-platform cutover
→ generate and independently qualify 2.6
```

The label `C32` is a reserved monotonic floor while 3.2.5 is `planned`. It is not an evidence-bearing candidate identity until exact source or package identity is frozen.

## Audit disposition

| Finding | Repository observation | Disposition | Planned record |
| --- | --- | --- | --- |
| Runtime research progress used an inverse conversion ratio and the first descriptor repair applied a correct ratio to a value Factorio had already normalized. | Confirmed by source inspection, the settings-change fixture, and direct 3.2.3-to-3.2.5 upgrade execution. | P0 package-visible correction before candidate freeze: retain the engine-normalized value without a second conversion. | `INC-2026-0054`, `CHG-2026-0007` |
| Base-continuation migration treated stable level-one coefficients as first-controlled-level costs. | Confirmed by the exact 3.2.3 source formula and the failed direct base-continuation upgrade row. | P0 package-visible correction before candidate freeze: project the stable coefficient onto the canonical model anchor and prove default parity. | `INC-2026-0057`, `CHG-2026-0007` |
| P11 remains public but has post-publication proof and stabilization obligations. | Confirmed by the typed 2.5.0 record and retained follow-up evidence. | P0 append-only reconciliation; do not rewrite publication history. | `CHG-2026-0011` |
| Ownership writes `product.balance`, but the semantic-domain catalog does not declare it. | Confirmed by the ownership and domain authorities. | P0 package-excluded referential-integrity repair. | `CHG-2026-0008` |
| Logical-path policy and durable Control Plane records still expose physical paths independently. | Confirmed during the dual-plane migration. | P0 package-excluded single-resolver cutover. | `CHG-2026-0009` |
| Planned 3.2.5 already exposes `candidate_id: C32`. | Confirmed in the typed release record and generated views. | P1 separate reservation from immutable candidate identity. | `CHG-2026-0010` |
| Research-cost identity includes provenance in one fingerprint. | Confirmed in `prototypes/mir/domain/research_cost/model.lua`. | P1 separate semantic, authority, and qualification digests. | `CHG-2026-0007` |
| Cost safety is primarily sampled and the external classifier lacks explicit resource budgets. | Confirmed in research-cost validation and classification. | P1 algebraic proof plus bounded numeric/parser envelopes. | `CHG-2026-0007` |
| Compatibility reporting, proof dimensions, exact environments, and support exports remain incomplete. | Already planned, with sharper audit requirements. | Complete as bounded 3.2.5 vertical slices. | `CHG-2026-0005` |
| The 3.3 endpoint needs an acyclic authority graph, planned mutation, runtime/migration kernel, and physical safety boundary. | Architectural refinement, not a 3.2.5 rewrite. | Stage behind fixed 3.2.5/latest-2.5.x baselines. | `CHG-2026-0012` |
| Evidence reuse needs proposition-bound identities, Merkle slices, batching rules, and hostile-mod isolation. | Control Plane v5 evolution. | Complete native observations and evaluators without rewriting v5. | `CHG-2026-0013` |
| Typed settings and ProcessIR remain prerequisites for broad safe customization and overhaul productivity. | Future product work. | Defer to 3.3.1+ and keep broad generation off. | `CHG-2026-0014` |
| 2.5.5 and 2.6 require deterministic target reconstruction, adapters, laws, and target-local proof. | Planned projection endpoint. | Feasibility before candidate; generate rather than hand-maintain. | `CHG-2026-0015` |
| MEP-1 needs a narrower stable surface and explicit finalization/continuity boundaries. | Refinement of the accepted extension programme. | Stable core in 3.3.0; experimental seams later. | `CHG-2026-0006` |

## P0 gate: research-cost transition correctness

Factorio exposes `LuaForce.research_progress` as a fraction in `[0,1]`. Preserving completed unit-equivalent work across a cost change requires:

```text
completed_work = old_fraction × old_cost
new_fraction   = completed_work / new_cost
               = old_fraction × old_cost / new_cost
```

The original runtime code instead multiplied by `new_cost / old_cost` and reparsed only a fixed count and two legacy exponential formula forms. The first descriptor repair corrected the algebra but missed that Factorio had already applied the completed-work normalization before MIR's configuration handler, so a second conversion still lost work.

The repair contract is:

1. Emit a compact versioned `CostTransitionDescriptor` for the input and output model of every adopted runtime family.
2. Bind formula ABI, anchor, base, linear increment, growth factor, semantic digest, and authority digest.
3. Evaluate both descriptors at the exact current technology level through one bounded canonical evaluator.
4. Verify Factorio's completed-work normalization against the source and current realized costs, and never apply the conversion a second time.
5. Preserve current research, queue order, completed levels, and unrelated force state.
6. Fail closed with a stable diagnostic when either model is unknown; do not expand runtime string parsing.
7. Make a second configuration change or reload idempotent.

Required transition matrix:

| From / to | Fixed | Linear | Exponential | Hybrid |
| --- | --- | --- | --- | --- |
| Fixed | required | required | required | required |
| Linear | required | required | required | required |
| Exponential | required | required | required | required |
| Hybrid | required | required | required | required |

Every row proves current technology, exact level, fractional progress, queue, completed levels, configuration change, save/reload, second reload, and continuous-versus-reload equivalence.

Official contract: [Factorio `LuaForce.research_progress`](https://lua-api.factorio.com/latest/classes/LuaForce.html).

## P0 gate: package-excluded authority migration

Before the first package-visible 3.2.5 freeze, package-excluded governance must establish:

```text
every task read domain exists
every task write domain exists
every ownership write domain exists
every downstream domain exists
every obligation alias source exists
every obligation alias target exists
every domain has one owner or an explicit composition rule
every source path resolves to one most-specific ownership rule
```

Ownership selection uses most-specific-pattern-wins. Equal specificity fails unless composition is explicit. Broad `scripts/**`, `validation/**`, and `.mir/**` fallbacks apply only when no specific rule matches. Unknown paths remain conservatively selected and fail governance.

Durable records store logical path IDs, not independent old and new physical paths. One resolver maps IDs such as `release.records`, `release.closures`, `evidence.objects`, `validation.schemas`, `tool.commands`, and `generated.views` to physical paths.

Migration is dual-read and single-write:

1. Read the canonical location and any declared legacy alias.
2. Write only the canonical location.
3. Compare legacy and canonical material.
4. Record a parity receipt.
5. Remove the alias only at its declared sunset release.

The exit gate is one release train, one path resolver, one semantic-domain graph, no contradictory current views, and no package change.

## P0 gate: P11 reconciliation

The immutable 2.5.0 package and publication facts are not rewritten. Add append-only post-publication records that:

1. Recover and verify retained observations.
2. Separate sound captures from invalid evaluation, aggregation, transport, or custody.
3. Re-evaluate sound observations through the corrected evaluator.
4. Produce exact missing performance proof against the final P11 identity.
5. Reproduce the exact BZ baseline/candidate environment.
6. Classify product, environment, and tooling outcomes deterministically.
7. Create P12/2.5.1 only for a confirmed package defect.
8. Record post-publication qualification or the replacement release.
9. Record the stabilization decision and target-local v5 calibration.

P11 closes only through complete post-publication proof or an independently qualified P12. Completing assurance alone does not justify an empty 2.5.1.

## P1 gate: candidate identity and append-only releases

The planned release record distinguishes:

```json
{
  "planned_candidate_floor": "C32",
  "reserved_candidate_id": "C32",
  "candidate_id": null
}
```

`candidate_id` becomes non-null only at `source-frozen` or `package-built`, after package-visible work and release schemas are complete. No observation, performance record, manual attestation, or release proof binds a reservation.

Once C32 is built, any package-byte change creates C33. Sealing prohibits rebuilds.

Published governance converges on immutable `ReleaseIdentityRecord`, append-only `ReleaseEvent`, append-only `PostPublicationQualification`, append-only `IncidentRecord`, and generated `ReleaseStatusView`. A later proof never appears as if it existed at publication time.

## P1 gate: three digest layers

Research costs and later stable authorities separate:

```text
semantic_digest
    formula ABI + anchor + base + increment + growth + derived kind

authority_digest
    semantic digest + provenance + setting IDs + source feature/profile + target disposition

qualification_digest
    authority digest + target + exact environment + observations + evaluator ABIs + proof closure
```

The same separation applies progressively to settings, feature fragments, compatibility dispositions, extension manifests, target projections, runtime features, and migration records. Equivalent semantics may be reused across different provenance only when authority and qualification requirements are independently satisfied.

## P1 gate: bounded and algebraically proven formulas

For nonnegative offsets:

```text
C(n) = (B + A n) G^n
B ≥ 1
A ≥ 0
G ≥ 1
```

Positivity and monotonicity follow from the parameter constraints. The primary proof is algebraic. Sampled levels remain regression characterization, not the safety argument.

The complete proof stack is:

```text
algebraic parameter proof
+ numeric operating-envelope proof
+ Factorio parser and realization tests
+ sampled high-level regression vectors
```

Govern explicit maximums for supported level, finite evaluated cost, formula length, token count, parse depth, AST nodes, and exponent magnitude. Unknown or over-budget external formulas are preserved or refused safely; they are never guessed.

## Bounded MIR 3.2.5 contract

MIR 3.2.5 must ship:

- complete fixed, linear, exponential, and hybrid cost models;
- descriptor-based runtime transitions and correct progress preservation;
- semantic/authority/qualification digest separation;
- bounded external formula classification and exact engine realization;
- one derived terminal disposition per leaf subject;
- independent proof dimensions for load, integrity, semantic behavior, progression, upgrade, configuration change, recovery, interaction, and performance;
- separate `EcosystemProfile`, `ExactEnvironmentLock`, and `ProofAssertion` authorities;
- deterministic JSON and localized summary-first support output;
- stable reason and remediation codes;
- effective-setting provenance;
- privacy-safe bounded support bundles;
- only refactors earned by these product slices and exact shadow parity;
- continuous Factorio 2.0 disposition and transport analysis.

The leaf terminal outcomes are `MIR_MATERIALIZED`, `OWNER_PRESERVED`, `OWNER_CONFIGURED`, `OWNER_ADOPTED`, `OWNER_REPLACED`, `DISABLED`, `OMITTED`, `REVIEW_REQUIRED`, and `FAILED`. Typed detail carries the reason; summaries do not collapse mixed ownership into a false single outcome.

The following remain deferred to 3.3: stable MEP-1, broad provider APIs, complete FeatureManifest and SettingSpec conversion, universal claim algebra, full lifecycle executor cutover, generalized runtime features, ProcessIR, the economy-loop solver, the full target generator, and broad complex-overhaul productivity.

## Improved 3.2.5 slices

### G0: authority migration

Complete domain/path integrity, candidate reservation semantics, generated-view schemas, append-only release events, P11 reconciliation, and C31 immutability without changing package bytes.

### F1: golden inputs

Freeze exact 3.2.3 and C31 identities, owners, formulas, evaluated costs, profiles, catalog, compiler result, plans, journals, realized prototypes, runtime storage, upgrade behavior, package composition, and performance counters. Add planned schemas for disposition, assertions, profiles, environments, support, semantic diffs, and cost transitions.

### F2: corrected cost slice

Implement descriptors, all 16 transitions, parser budgets, algebraic safety, numerical envelope, engine oracles, cross-language vectors, profile migration, default parity, and target disposition. Exit only when no cost/progress difference is unexplained and continuous execution equals save/reload.

### F3: derived dispositions in shadow

Start with Base and Space Age. Every leaf binds observed facts, planned/applied/realized results, terminal outcome, reasons, remediations, effective settings, source authorities, semantic digest, and qualification digest. Report failure cannot alter compilation.

### F4: proof and ecosystem authorities

Begin with Base, Space Age, and the P11/BZ profile. Add further exact profiles according to available closures and risk, promoting each proof dimension independently.

### F5: support, privacy, and localization

Prove summary-first output, localized explanations, stable machine codes, pseudo/long locales, placeholder contracts, redaction, resource budgets, truncation counts, and diagnostics-off parity.

### F6: earned consolidation

Remove an old path only after old producer, shadow producer, exact differential, measured benefit, rollback point, and target disposition exist. Do not combine mass reorganization with semantic refactoring.

### F7: continuous Factorio 2.0 projection

Classify every slice as portable-identical, portable-with-adapter, target-native-equivalent, omitted-by-capability, target-specific, tooling-only, or unsupported-with-evidence. Continuously prove stable IDs, costs, profiles, dispositions, migrations, report transport, performance, and reconstruction.

### F8: first real candidate

Assign C32 only after every package-visible slice, release schema, transition, approved-delta policy, target disposition, public API diff, manual scope, Control Plane ABI, and release document is complete. Build once; any later package change increments the candidate.

## Conditional MIR 2.5.5

Create a `ProjectionFeasibilityRecord` before any release record:

```yaml
source_release: 3.2.5
target_baseline: latest-qualified-2.5.x
target: factorio-2.0
state: investigating
```

Publish only when every modern change has a target disposition, no second compiler or policy authority is needed, stable IDs and costs project, support output remains useful, runtime and migration behavior is defined, tree and package reconstruct twice, exact target closures exist, and performance is acceptable. Otherwise preserve the feasibility report and defer the repair to 3.3/2.6.

## MIR 3.3 platform corrections

MIR 3.3 evolves the existing snapshot, policy, catalog, result, plans, journal, compiler evidence, and external Control Plane evidence into one graph of versioned authorities. It does not introduce parallel writable WorldIR, PolicyIR, PlanIR, or Lua EvidenceIR objects.

Required corrections include:

- a desired acyclic semantic dependency graph rather than an observed cyclic allowlist;
- `FeatureManifest` as an aggregate index over independently owned fragments;
- separate static `FeatureTypeSpec` and dynamically discovered `FeatureInstance`;
- stage-bounded SettingsRegistry, ExtensionRegistry, and RuntimeRegistry;
- a physically separated, non-overridable SafetyKernel;
- a PolicyEngine that selects only among legal outcomes;
- field-specific merge laws with property tests;
- one provenance envelope compiled into specialized settings, normalization, mutation, runtime, migration, and publication plans;
- zero direct prototype writes outside stage executors;
- a split pure compilation pipeline and explicit `CompilationRun` references;
- explicit CompilerContext flow, typed stores, phase access, structural sharing, and memoized digests;
- a generated runtime kernel with state schemas, migrations, deterministic subscriptions, and bounded complexity.

Runtime migrations are classified as reversible, forward-only-nondestructive, forward-only-destructive, repair-only, or tombstone. Universal downgrade is not promised. Every runtime feature has one forward path, idempotent configuration reconciliation, continuous-versus-reload equivalence, and explicit removal behavior.

## MEP-1 stable boundary

Stable in 3.3.0:

```text
CompatibilityFragment
ProfileFragment
ProofFragment
PresentationFragment
CapabilityNegotiation
ExtensionDependency and ExtensionConflict declarations
```

Experimental or deferred until their narrower contracts are proven:

```text
DeclarativeProviderFragment
StaticSettingContribution
RuntimeDescriptor
TrustedAdapterV1
```

Registration and finalizer ordering remain separate. Settings fragments register no later than settings-updates; prototype fragments register no later than data-updates; data-final-fixes observations require an explicit `FinalizationRequirement`. An unsatisfied relation produces diagnostic or review-required status, never a false support claim.

MEP remains host-neutral and offline. A differently named fork can consume data-stage manifests but does not inherit another mod's runtime storage; successor packages require a documented migration bridge.

## Settings and ProcessIR

The future typed settings authority uses values such as basis points, ratios, probabilities, science units, durations, level limits, derived values, inherit, and disabled. Override layers run from safe and target defaults through ecosystem/modpack/user profiles to explicit overrides and a final hard-safety clamp. Dynamic prototype-stage instances use sparse selectors; they do not create startup settings retroactively.

ProcessIR derives from canonical recipe facts rather than rescanning prototypes. It models quantities, probabilities and correlations, productivity-sensitive amounts, catalysts, returned containers, recycling, quality/spoilage, surfaces, machines, unlocks, owners, and provenance. Positive-yield-loop certification is hard safety and precedes broad productivity for complex overhaul processes.

## Assurance and CI evolution

Control Plane v5 remains the base. Add bounded pure evaluators, four proof identities, Merkle-sliced observations, semantic impact closure, compatible-environment batching, explicit freshness, and supply-chain role isolation.

```text
CaptureKey     = Factorio + exact mod closure + upstream settings + load order
CompilationKey = snapshot + policy + compiler ABI
RealizationKey = accepted plans + candidate + target executor
EvaluationKey  = observation digest + assertion + evaluator ABI
```

External-mod runners are disposable and secretless; protected aggregators verify but do not execute arbitrary new closures; publishers receive sealed bytes and cannot rebuild. Scheduling data may optimize order and placement, never omit required proof.

## Target projection endpoint

```text
immutable MIR 3.3 source
+ latest qualified 2.5.x baseline
+ machine-derived Factorio 2.0 capability certificate
+ hand-authored semantic target policy
+ reviewed adapter set
+ release overlay
= exact MIR 2.6 package
```

Adapters cover metadata, dependencies, prototype shapes, product fields, science, effects, report transport, runtime storage, omissions, assets, migrations, and release text. Each proves round-trip where meaningful, preservation of unowned fields, idempotence, locality, and target semantic parity. The generated tree reconstructs without a pre-existing projection branch; the dual-parent commit records provenance rather than becoming the only build mechanism.

## Immediate execution order

1. Add `product.balance` and strict semantic-domain referential integrity.
2. Make logical path IDs the only durable path authority.
3. Enforce most-specific ownership and explicit composition.
4. Reconcile P11 protected retry, performance binding, BZ result, and stabilization.
5. Add append-only post-publication qualification records.
6. Replace planned candidate identity with a reserved candidate floor.
7. Split research-cost semantic, authority, and qualification digests.
8. Replace runtime formula parsing with versioned descriptors.
9. Correct research-progress conversion.
10. Add all 16 cost-transition rows.
11. Add parser and numeric resource limits plus algebraic proof.
12. Freeze 3.2.3 and C31 golden semantic baselines.
13. Implement Base and Space Age dispositions in shadow.
14. Enforce exactly one terminal result per leaf.
15. Add ProofAssertion, EcosystemProfile, and ExactEnvironmentLock.
16. Qualify Base, Space Age, and P11/BZ first.
17. Implement bounded support output and privacy gates.
18. Continuously materialize Factorio 2.0 dispositions and report transport.
19. Complete only refactors earned under shadow parity.
20. Freeze C32 after all package-visible work is complete.
21. Complete focused, candidate, manual, protected, seal, promotion, and publication gates.
22. Run 2.5.5 feasibility from immutable 3.2.5.
23. Freeze 3.2.5 and latest-2.5.x behavioral baselines.
24. Execute the 3.3 platform milestones.
25. Generate and independently qualify 2.6.

## Non-negotiable gates

The programme admits no direct prototype writes outside executors, global CompilerContext access from pure domain code, unversioned public schemas, unnamespaced extension IDs, dynamic settings after freeze, external hard-safety overrides, unclassified target dispositions or package paths, undeclared semantic domains, ambiguous path owners, writes outside declared sets, adapters that fail preservation laws, runtime state without migration, stale current claims, revoked sealed proof, impact false negatives, unique target logic on temporary branches, candidate rebuilds after sealing, or lost completed observations.

## Engineering objectives

| Operation | Objective |
| --- | ---: |
| Pure specification/compiler edit | Under 30 seconds |
| Focused static/generation check | 1–3 minutes |
| Locale/package-only change | Under 5 minutes |
| Assertion/evaluator-only change | Seconds |
| One affected Factorio environment | One capture plus offline evaluations |
| Narrow candidate qualification | Roughly 15–30 minutes excluding manual work |
| Full protected no-reuse calibration | Roughly 45–60 minutes |
| Target reconstruction | One deterministic command |
| Impact, reuse, and evidence-loss false outcomes | Zero |

Track selection ratio, Factorio processes, proofs per process, reuse ratio, critical path, evidence and canonicalization bytes, fingerprint calls, deep copies, graph scans, claims, conflicts, operations, runtime handlers, and nondeterminism incidents.

## Completion

This register is complete only when every planned record has either qualified implementation evidence, a preserved deferral with reason and target, or an explicit not-applicable proof. Documentation must not convert these plans into current compatibility, candidate, or release claims.
