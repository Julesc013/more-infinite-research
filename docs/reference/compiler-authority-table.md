---
title: "Compiler Authority Table"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-23
supersedes: []
superseded_by: []
---

# Compiler Authority Table

This table names one machine authority, validator, and reference contract for each automatic-compiler surface. A schema change is incomplete until code, governed manifests, reference docs, fixtures, and this table move together.

| Surface | Schema | Machine authority | Validator | Primary consumer |
| --- | ---: | --- | --- | --- |
| Effect metadata | 1 | `prototypes/mir/domain/effects/metadata.lua` | `scripts/Test-MIRCompilerSchemaDrift.ps1` | effect contracts, settings, ownership, emission |
| Effect target contracts | 1 | `.mir/technology-effect-targets.json` and generated `domain/effects/generated_target_contracts.lua` | `Update-MIRCompilerAuthorities.ps1 -Check` | pure target identity and validation contracts |
| Stable generated streams | 1 | `prototypes/mir/streams/generated_stream_manifest.json` | `scripts/Test-MIRGoldenPlans.ps1` | stream registry and migration policy |
| Canonical StreamSpec descriptor | 1 | `prototypes/mir/domain/streams/descriptor.lua` | `scripts/Test-MIRArchitecture.ps1` | settings and GenerationPlan compilation |
| FamilyRule | 2 | `prototypes/mir/families/rules.lua` | `prototypes/mir/families/registry.lua` | structural family resolver |
| CompilerProvider | 1 | `prototypes/mir/providers/contract.lua` | `prototypes/mir/providers/registry.lua` and compiler-contract fixture | normalized FamilyRule provider adapter |
| Provider pipeline and budget | 1 | `prototypes/mir/providers/pipeline/` | compiler-contract and scale fixtures | schema-3 ProviderDecision projection |
| ProviderMetrics | 1 | `prototypes/mir/providers/provider_metrics.lua` | compiler-contract fixture and TechnologyQualityAssessment | exact provider/environment measurements and provenance |
| ProviderClaim | 1 | `prototypes/mir/providers/pipeline/provider_claim.lua` | compiler-contract provider matrix | semantic duplicate collapse and ambiguity rejection |
| CompatibilityPack | 2 | `prototypes/mir/compatibility/packs/schema.lua` | `prototypes/mir/compatibility/packs/registry.lua` | pack filtering, precedence, ownership policy |
| TechnologyDesign | 2 | `prototypes/mir/domain/technology/technology_design.lua` | schema validator, semantic schema-drift checks, and compiler-contract fixture | normalized fixed and automatic stream planning and emission |
| Technology hard gate | 1 | `.mir/technology-hard-gates.json`, generated hard-gate authority, and `gate.lua` | GenerationPlan, SafetyQualification, and compiler-contract fixture | total evidence-bearing decisions including N/A applicability proof |
| SafetyQualification | 1 | `prototypes/mir/domain/technology/safety_qualification.lua` | TechnologyCatalog and compiler-contract fixture | deterministic selection eligibility |
| DesignAssessment | 1 | `prototypes/mir/domain/technology/design_assessment.lua` | lifecycle and compiler-contract fixtures | design review independent from safety |
| PromotionAuthorization | 1 | `.mir/technology-governance.json`, generated `promotion_registry.lua`, and `promotion_authorization.lua` | governance generator check, CompatibilityPack registry, and compiler-contract fixture | reviewed automatic creation trust |
| TechnologyQualityAssessment | 2 | `prototypes/mir/domain/technology/technology_quality_assessment.lua` and `.mir/technology-quality-profiles.json` | lifecycle and compiler-contract fixtures | monotonic complete/incomplete quality result |
| TechnologyCatalog | 3 | `prototypes/mir/planner/technology_catalog.lua` and `technology_selection_policy.lua` | exact GenerationPlan/CompilationPlan projection and compiler-contract fixture | canonical post-graph alternative inventory and current selection |
| GenerationPlan | 3 | `prototypes/mir/planner/generation_plan.lua` | whole-plan finalization, output validation, and compiler-contract fixture | transaction and emission layers |
| CompilationPlan | 2 | `prototypes/mir/planner/compilation_plan.lua` | global operation finalization and output parity | governed stream and base-extension emission |
| CompilationSnapshot | 1 | `prototypes/mir/domain/compiler/compilation_snapshot.lua` | compiler-contract replay and tamper tests | immutable normalized compiler state input |
| PolicySnapshot | 1 | `prototypes/mir/domain/compiler/policy_snapshot.lua` | compiler-contract replay and authority tests | immutable settings, policy, gate, quality, and promotion input |
| CompilerInput | 2 | `prototypes/mir/domain/compiler/compiler_input.lua` | compiler-contract fixture | exact snapshot, policy, sanitation, and runtime-environment request |
| CompilerResult | 2 | `prototypes/mir/domain/compiler/compiler_result.lua` | compiler-contract fixture | multidimensional execution, safety, review, promotion, and release result |
| RuntimeEnvironmentIdentity | 2 | `prototypes/mir/domain/environment_identity.lua` and Factorio adapter | compiler-contract fixture | exact target, mod closure, settings, policy, and promotion identity |
| QualificationEnvironmentIdentity | 1 | `prototypes/mir/domain/qualification_environment_identity.lua` | assurance seal and schema tests | candidate, binary, runner, verifier, plan, test-set, and trust identity |
| TransformationOperation | 1 | `prototypes/mir/domain/compiler/transformation_operation.lua` | compiler-contract and mutation journal tests | common create/patch/delete envelope |
| TransformationPlan | 1 | `prototypes/mir/domain/compiler/transformation_plan.lua` | pure compiler replay tests | canonically ordered qualified mutation plan |
| MutationJournal | 1 | `prototypes/mir/domain/compiler/mutation_journal.lua` | executor and compiler-contract tests | before/after evidence for every applied transformation |
| Compiler orchestration | 1 | `prototypes/mir/pipeline/compiler_orchestrator.lua` | architecture gate and compiler-contract fixture | compile/apply/assert/publish sequencing and context ownership |
| Shared technology graph | 1 | `prototypes/mir/graph/` | planner/emitter parity and compiler-contract fixtures | virtual and realized graph qualification |
| CompilerContext | 4 | `prototypes/mir/pipeline/compiler_context.lua` | architecture and A/B/A nested-context fixtures | scoped activation, run-owned services, state epochs, caches, and artifacts |
| CompilerEvidence | 2 | `prototypes/mir/domain/evidence/compiler_evidence.lua` | postcondition publication, transport adapters, and content fingerprints | assurance evidence and sanitation review |
| Public compiler artifact projections | 1 | `prototypes/mir/report/public_compiler_artifacts.lua` | architecture gate and compiler-contract fixtures | normal-load `mod-data` publication |
| RecipeFactV2 | 2 | `prototypes/mir/index/recipe_facts.lua` | generation-integrity and compiler fixtures | rules, safety, coverage, ownership |
| Runtime scenario declaration | 3 | `fixtures/compat-matrix/expected-scenarios.json` | `scripts/validation/ScenarioRegistry.ps1` | validation harness |
| Campaign scenario declaration | 2 | `fixtures/compat-matrix/local-library-scenarios.json` | `scripts/Test-MIRScenarioManifests.ps1` | compatibility audit runner |

`prototypes/mir/settings/effect_contracts.lua` consumes effect metadata and may add setting defaults, but it is not a second effect classification authority. Compatibility data cannot create stream or technology identities. Every generated technology identity remains in the stable stream manifest.
