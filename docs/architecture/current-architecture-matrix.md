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
| Family selection | `FamilyRule` plus schema-3 `ProviderDecision` in `families/resolver.lua` | stream compiler and capability diagnostic adapters | none | diagnostic decision fingerprint equals planner decision fingerprint; no second discovery pass |
| Provider expansion | registered `CompilerProvider` policy and its cardinality contract | family resolver | none | overflow becomes `REVIEW_REQUIRED`; it never emits silently |
| Compilation lifetime | schema-2 `CompilerContext` | every run-derived cache and artifact | context state only | separate contexts share no recipe, science, progression, catalog, diagnostic, or telemetry state |
| Technology alternatives | schema-2 `TechnologyCatalog` | preview, review dossier, quality assessment, promotion gate | none | catalog exists before current selection is bound; every alternative has an exact qualification |
| Quality | `TechnologyQualityAssessment` plus a governed profile | review and promotion admission | none | exact candidate, design, qualification, profile, metrics, evidence, and assessment fingerprint |
| Promotion | `TechnologyPromotionAdmission` | release governance | none | passing assessment, exact approval/envelope/evidence, one identity edge, migration policy, locked fields |
| Planning | GenerationPlan schema 3 and CompilationPlan schema 2 | emitters and validators | none | complete gates, exact design projection, deterministic fingerprints |
| Graph safety | `planner/technology_graph.lua` before emission and `emit/technology_graph_safety.lua` after emission | CompilationPlan and final assertion | none | exact node/prerequisite parity, enabled nodes, accepted SCC proof, reachable science and lab |
| Emission | `emit/technology_design_adapter.lua`, stream executor, and bounded transactions | Factorio prototype table | generated technology creation and authorized patch-existing operations only | output validator matches exact planned projections |
| Reporting | public artifact projector and diagnostics sink | mod-data, log, offline tooling | none | compact public artifacts; detailed internal artifacts only in diagnostics or preview mode |

## Non-duplication rules

- CapabilityResolver remains an adapter over ProviderDecision for loader and mining-family diagnostics; it does not rediscover entities or recipes.
- Compatibility packs reference canonical risk facts and may resolve review flags only. They cannot override hard risk.
- The schema-2 candidate catalog is a shadow decision artifact. It cannot emit, patch, register, promote, or publish a technology.
- Final graph validation reports actual emitted/planned parity. It does not expose placeholder cycle collections.
- All science, progression, provider, catalog, diagnostic, and telemetry caches belong to the active CompilerContext.

## C5 and C6 boundary

C5 remains the immutable 935,250-byte archive identified in the release authority. This architecture hardening changes packaged Lua and therefore produces C6 only after deterministic packaging records the new exact archive, content, and package-source identities. Qualification evidence must bind that registered C6 and its definitive post-freeze plan.
