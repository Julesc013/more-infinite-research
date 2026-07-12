---
title: "Compiler Authority Table"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Compiler Authority Table

This table names one machine authority, validator, and reference contract for each automatic-compiler surface. A schema change is incomplete until code, governed manifests, reference docs, fixtures, and this table move together.

| Surface | Schema | Machine authority | Validator | Primary consumer |
| --- | ---: | --- | --- | --- |
| Effect metadata | 1 | `prototypes/mir/domain/effects/metadata.lua` | `scripts/Test-MIRCompilerSchemaDrift.ps1` | effect contracts, settings, ownership, emission |
| Stable generated streams | 1 | `prototypes/mir/streams/generated_stream_manifest.json` | `scripts/Test-MIRGoldenPlans.ps1` | stream registry and migration policy |
| Canonical StreamSpec descriptor | 1 | `prototypes/mir/domain/streams/descriptor.lua` | `scripts/Test-MIRArchitecture.ps1` | settings and GenerationPlan compilation |
| FamilyRule | 2 | `prototypes/mir/families/rules.lua` | `prototypes/mir/families/registry.lua` | structural family resolver |
| CompatibilityPack | 2 | `prototypes/mir/compatibility/packs/schema.lua` | `prototypes/mir/compatibility/packs/registry.lua` | pack filtering, precedence, ownership policy |
| GenerationPlan | 3 | `prototypes/mir/planner/generation_plan.lua` | whole-plan finalization, output validation, and compiler-contract fixture | transaction and emission layers |
| CompilationPlan | 2 | `prototypes/mir/planner/compilation_plan.lua` | global operation finalization and output parity | governed stream and base-extension emission |
| RecipeFactV2 | 2 | `prototypes/mir/index/recipe_facts.lua` | generation-integrity and compiler fixtures | rules, safety, coverage, ownership |
| Runtime scenario declaration | 3 | `fixtures/compat-matrix/expected-scenarios.json` | `scripts/validation/ScenarioRegistry.ps1` | validation harness |
| Campaign scenario declaration | 2 | `fixtures/compat-matrix/local-library-scenarios.json` | `scripts/Test-MIRScenarioManifests.ps1` | compatibility audit runner |

`prototypes/mir/settings/effect_contracts.lua` consumes effect metadata and may add setting defaults, but it is not a second effect classification authority. Compatibility data cannot create stream or technology identities. Every generated technology identity remains in the stable stream manifest.
