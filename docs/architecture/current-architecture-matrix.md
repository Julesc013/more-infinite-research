---
title: "Frozen MIR 3 Compiler Architecture Matrix"
status: archived
applies_to: "MIR3 terminal family"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-08-04
supersedes: []
superseded_by:
  - docs/architecture/mir4-r0-bootstrap.md
---

# Frozen MIR 3 Compiler Architecture Matrix

This matrix is the frozen operational map for the MIR 3 compiler and release-engineering boundary. It remains authoritative for reconstructing the terminal family, but it is no longer the current successor-programme view. MIR 4 R0 imports these proven boundaries and migrates one owner at a time.

| Concern | Canonical authority | Consumers | Mutation authority | Required parity or evidence |
| --- | --- | --- | --- | --- |
| Recipe semantics | `RecipeFactV2` in `index/recipe_facts.lua` | relationships, science, risk facts, matching | none | one context-owned index and deterministic fingerprint |
| Recipe risk | `RecipeRiskFact` in `index/recipe_risk_facts.lua` | FamilyRule evaluation, ProviderDecision, packs, GenerationPlan, diagnostics | none | identical risk fingerprint at every boundary; hard risk cannot be overridden |
| Family selection | explicit provider pipeline ending in schema-3 `ProviderDecision` | stream compiler and capability diagnostic adapters | none | immutable discovery, normalization, classification, pack, hazard, owner, decision, and budget stages; no second discovery pass |
| Provider expansion | registered `CompilerProvider`, schema-1 `ProviderMetrics`, and scoped budget policy | family resolver and quality assessment | none | exact environment, partition, dispositions, depth, conflicts, time, bytes, witnesses, provenance, and completeness |
| Compilation lifetime | schema-4 `CompilerContext` | every run-derived cache, service, and artifact | context state only | scoped packed activation, context-owned frozen services, explicit state epochs, compact public snapshots, and no cross-context state |
| Compiler boundary | normalized schema-2 `CompilationSnapshot`, schema-1 `PolicySnapshot`, schema-2 `CompilerInput`, schema-3 `CompilerResult`, and schema-2 runtime identity | pure compiler, compatibility finalizer, and orchestrator | none | structurally shared fact domains plus exact input, planned/final result, environment, plan, journal, and qualification fingerprints |
| Research-cost semantics | bounded canonical cost evaluator, semantic and authority digests, and `mir-research-cost-transition-v1` old/new descriptor | planner, runtime configuration-change observation, upgrade fixtures, and diagnostics | Factorio normalizes active progress for prototype-cost changes; MIR must not apply a second conversion | fixed, linear, exponential, and hybrid algebra; sixteen transition pairs; source-work/current-cost preservation; fail-closed unknown, tampered, and over-budget inputs; exact reload parity |
| Internal record trust | module-private weak-key authorities in `core/trusted_record.lua` | gates, designs, qualifications, candidates, catalogs, transformation operations, and transformation plans | constructors and explicit import verifiers only | untrusted records receive one complete schema/cross-field/fingerprint verification; compiler-owned immutable records use cheap identity assertions; snapshots and final output remain defensive deep-verification boundaries |
| Technology alternatives | canonical post-graph schema-3 `TechnologyCatalog` plus deterministic selection policy | GenerationPlan, CompilationPlan, preview, review dossier, assessment | none | rejected designs and total gates survive; both plans are exact projections |
| Hard safety | `SafetyQualification` and evidence-bearing gate records | catalog selection and CompilationPlan | none | pending is proposal; passed/failed bind evaluator and evidence; provisional gates are superseded explicitly |
| Quality | `DesignAssessment` and schema-2 `TechnologyQualityAssessment` | review and promotion admission | none | mandatory profile, per-metric provenance, monotonic status, and incomplete is review-required |
| Reviewed trust | generated MIR-owned `PromotionAuthorization` registry | compatibility packs and automatic creation policy | none | source is `.mir/technology-governance.json`; only `mir-reviewed` and `protected-release` can authorize reviewed creation |
| Promotion | `TechnologyPromotionAdmission` | release governance | none | passing assessment, exact approval/envelope/evidence, one identity edge, migration policy, locked fields |
| Planning | GenerationPlan schema 3 and pure CompilationPlan schema 2 | orchestrator, emitters, and validators | none | complete gates, exact design projection, deterministic fingerprints, and zero planner-to-emit imports |
| Graph safety | shared `graph/` kernel with planner and emitter adapters | CompilationPlan and final assertion | none | virtual and realized snapshots share SCC, condensation, researchability, diff, and proof semantics plus exact fingerprints |
| Presentation | `presentation/icon_builder.lua` | planning, diagnostics, and emitter facade | none | presentation construction has no dependency on mutation modules |
| Emission | exact schema-2 TransformationPlan, plan-bound MutationJournal, `emit/technology_design_adapter.lua`, and the shared technology-operation executor | Factorio prototype table | generated technology creation and authorized patch-existing operations only | every mandatory operation proves exact before/after state; missing, duplicate, undeclared, failed, or out-of-plan work fails closed |
| Reporting | governed public-artifact budgets, public artifact projector, diagnostics sink, and offline dossier/export tooling | mod-data, log, validation, reviewer tooling | none | compact bounded public artifacts; detailed internal artifacts only in diagnostics or preview mode; byte overflow fails publication |
| Repository authority | logical path IDs resolved through `tools/lib/workspace/RepoPaths.ps1`, typed `.mir/` records, and generated compatibility views | control plane, assurance, validation, documentation, and maintainer commands | typed-record commands and explicitly governed generators only | one durable logical authority per path or fact; aliases are read-only; generated views fail freshness checks when stale |
| Release planning and identity | typed `ReleaseRecord` plus append-only transition and closure records | assurance plans, generated release views, package locks, sealing, and promotion | release controller only | planned reservation and exact candidate identity are separate; pre-candidate plans bind a source snapshot but grant no candidate authority; source freeze and later states require monotonic exact identity and proof |

## Non-duplication rules

- CapabilityResolver remains an adapter over ProviderDecision for loader and mining-family diagnostics; it does not rediscover entities or recipes.
- Compatibility packs reference canonical risk facts and may resolve review flags only. They cannot override hard risk.
- The schema-3 candidate catalog is finalized after sanitation and graph proof as the canonical inventory. It cannot emit, patch, register, or promote a technology; the orchestrator publishes its exact artifact.
- Final graph validation reports actual emitted/planned parity. It does not expose placeholder cycle collections.
- All science, progression, provider, catalog, diagnostic, telemetry, services, and state epochs belong to the active CompilerContext.
- A copied or decoded record is untrusted even when all of its public fields match a trusted record. It must pass `verify_untrusted`; a public `validated` flag cannot confer authority.
- Trusted assertions never canonicalize complete records. Normal compilation performs no full catalog snapshot or full TechnologyDesign copy, and governed work-volume counters make regressions visible independently of wall-clock noise.
- Aggregate snapshot, catalog, transformation-operation, transformation-plan, and pure-compilation identities are Merkle-style projections over exact stored component fingerprints. They do not embed complete trusted designs or qualifications a second time.
- `.mir/module-dependencies.json` and `Test-MIRModuleDependencies.ps1` enforce the exhaustive cross-layer matrix, reject every planner-to-emitter import, and permit no exception.

## Candidate boundary

Historical candidate archives remain immutable in release authority. The current development reservation or candidate and all archive, package-source, and qualification fields are generated in [Current Development Candidate](../releases/current-candidate.md) from the typed `.mir/releases/records/3.2.5.json` authority; `.mir/releases.json` is only a generated compatibility projection. This architecture document does not duplicate mutable candidate identity. Qualification evidence transfers only when every bound package and assurance fingerprint is identical.
