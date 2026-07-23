---
title: "Current MIR Compiler Architecture Matrix"
status: current
applies_to: "3.2.0-dev"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Current MIR Compiler Architecture Matrix

This matrix is the current operational map for the MIR 3.2 compiler. Historical release reports explain how individual layers arrived here; they do not override these ownership boundaries.

| Concern | Canonical authority | Consumers | Mutation authority | Required parity or evidence |
| --- | --- | --- | --- | --- |
| Recipe semantics | `RecipeFactV2` in `index/recipe_facts.lua` | relationships, science, risk facts, matching | none | one context-owned index and deterministic fingerprint |
| Recipe risk | `RecipeRiskFact` in `index/recipe_risk_facts.lua` | FamilyRule evaluation, ProviderDecision, packs, GenerationPlan, diagnostics | none | identical risk fingerprint at every boundary; hard risk cannot be overridden |
| Family selection | explicit provider pipeline ending in schema-3 `ProviderDecision` | stream compiler and capability diagnostic adapters | none | immutable discovery, normalization, classification, pack, hazard, owner, decision, and budget stages; no second discovery pass |
| Provider expansion | registered `CompilerProvider` plus scoped budget policy | family resolver | none | exact-reviewed attachments and hard blockers survive; only new-unreviewed proposals are suppressible |
| Compilation lifetime | schema-3 `CompilerContext` | every run-derived cache, service, and artifact | context state only | context-owned frozen services, explicit state epochs, pure snapshots, and no cross-context state |
| Technology alternatives | canonical schema-2 `TechnologyCatalog` plus deterministic selection policy | GenerationPlan, preview, review dossier, assessment | none | catalog always exists before selection; GenerationPlan is its exact projection |
| Hard safety | `SafetyQualification` and evidence-bearing gate records | catalog selection and CompilationPlan | none | pending is proposal; passed/failed bind evaluator and evidence; provisional gates are superseded explicitly |
| Quality | `DesignAssessment` and `TechnologyQualityAssessment` | review and promotion admission | none | quality cannot be inferred from safety or trust |
| Reviewed trust | MIR-owned `PromotionAuthorization` registry | compatibility packs and automatic creation policy | none | exact named reference; only `mir-reviewed` and `protected-release` can authorize reviewed creation |
| Promotion | `TechnologyPromotionAdmission` | release governance | none | passing assessment, exact approval/envelope/evidence, one identity edge, migration policy, locked fields |
| Planning | GenerationPlan schema 3 and CompilationPlan schema 2 | emitters and validators | none | complete gates, exact design projection, deterministic fingerprints |
| Graph safety | shared `graph/` kernel with planner and emitter adapters | CompilationPlan and final assertion | none | virtual and realized snapshots share SCC, condensation, researchability, diff, and proof semantics plus exact fingerprints |
| Presentation | `presentation/icon_builder.lua` | planning, diagnostics, and emitter facade | none | presentation construction has no dependency on mutation modules |
| Emission | `emit/technology_design_adapter.lua`, stream executor, and bounded transactions | Factorio prototype table | generated technology creation and authorized patch-existing operations only | output validator matches exact planned projections |
| Reporting | public artifact projector and diagnostics sink | mod-data, log, offline tooling | none | compact public artifacts; detailed internal artifacts only in diagnostics or preview mode |

## Non-duplication rules

- CapabilityResolver remains an adapter over ProviderDecision for loader and mining-family diagnostics; it does not rediscover entities or recipes.
- Compatibility packs reference canonical risk facts and may resolve review flags only. They cannot override hard risk.
- The schema-2 candidate catalog is always built as the canonical inventory. It cannot emit, patch, register, promote, or publish a technology.
- Final graph validation reports actual emitted/planned parity. It does not expose placeholder cycle collections.
- All science, progression, provider, catalog, diagnostic, telemetry, services, and state epochs belong to the active CompilerContext.
- `.mir/module-dependencies.json` and `Test-MIRModuleDependencies.ps1` reject forbidden planner-to-emitter imports and unreviewed dependency cycles.

## C5, C6, and C7 boundary

C5 and C6 remain immutable archives identified in release authority. The fixed-point compiler work changes packaged Lua and therefore becomes C7 after deterministic packaging records exact archive, content, package-source, and entry-count identities. Qualification evidence must bind registered C7 and a definitive post-freeze C7 plan; no earlier candidate evidence transfers.
