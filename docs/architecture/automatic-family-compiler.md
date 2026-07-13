---
title: "Automatic Family Compiler"
status: current
applies_to: "3.1.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# Automatic Family Compiler

## Modular Provider Boundary

MIR 3.1.5 defines `CompilerProvider` schema 1 as the extension boundary above FamilyRule. Built-in machine, logistics, mining, module, laboratory, furnace, and power families are registered through the same sorted data-only registry that future families use. Each row declares its source kinds, final-fact discovery indexes, positive capabilities, normalization and semantic identity, policy and setting references, validation hooks, planning adapter, runtime requirement, migration identity, diagnostic codes, and fixtures.

Providers cannot mutate prototypes. Their adapter produces planner input; FamilyRule resolution produces declarative candidate and attachment records; GenerationPlan and CompilationPlan arbitrate ownership and validate identities; emission alone materializes technologies. Duplicate provider IDs, behavioral descriptors, registry-order drift, direct mutation claims, and provider/family identity mismatches fail before planning.

The semantic stages are discovery, normalization, identity, capability classification, policy, planning, graph construction, validation, emission, runtime registration, and diagnostics/evidence. Runtime registration is absent unless a provider explicitly uses a separately governed handler. Candidate records retain the provider ID, source key and prototype identity, family, final state, capabilities, recipe/item target, policy scope, stable identity seed, diagnostic provenance, target support, and emission ownership.

MIR 3.0.5 is the published immutable behavior baseline. MIR 3.1.0 turns its fixed declarative stream compiler into a plan-first semantic family compiler on `dev`. Earlier 3.1.0 candidate artifacts and tags are superseded development evidence, not published release authority.

## Pipeline Contract

```text
final prototype state
-> RecipeFactV2 and shared indexes
-> data-only FamilyRule registry
-> capability candidates and decisions
-> pure GenerationPlan schema 3
-> globally finalized CompilationPlan schema 2
-> emission
-> full output-shape parity
-> diagnostics and golden-plan evidence
```

Planning is side-effect free. Only modules under `prototypes/mir/emit/` may create or mutate generated technology prototypes. Reporting materializes decisions; it is not an alternative mutation path.

`GenerationPlan` is the stream intermediate representation. Schema 3 records stable stream identity, technology identity, effects, science, prerequisites, cost, migration policy, evidence, blockers, risks, source provenance, evidence-bearing proof gates, source fingerprints, and a deterministic plan fingerprint. `CompilationPlan` schema 2 then unifies materializing stream, adoption, and base-extension operations, applies reviewed cross-operation policy such as weapon-effect ownership, rejects global collisions, and fingerprints the finalized envelope before the first generated prototype is emitted. Final parity checks numeric effects and full technology shape.

`DecisionRecordV2` keeps typed evidence classes instead of treating a formatted confidence string as authority. Confidence ranks review evidence; hard safety gates remain independent pass/fail records and cannot be averaged into an emission decision.

## Compatibility And Identity Boundary

- Preserve all 70 released stream and technology IDs.
- First automatic behavior is attach-only: high-confidence recipes may join an existing stable stream. It creates no per-recipe technology IDs.
- Predeclared family technologies require an explicit manifest row and migration review before emission is enabled.
- Ambiguous, risky, loop-forming, hidden, or externally owned candidates remain proposal-only or diagnostic-only.
- Compatibility packs contain selectors, policy, expected decisions, and claim metadata. They do not read `data.raw` or mutate prototypes. Hard safety facts are never data-overridable.
- The schema-2 automatic compiler policy separates action (`disabled`, `preview`, or `apply`) from research creation and reviewed-data requirements. The policy names no mods, recipes, technologies, or Factorio versions.
- When reviewed compatibility data is required, emission needs an active exact-version, fixture-backed generation authorization for that registered family.
- A reviewed candidate seed may add one exact recipe to an existing FamilyRule and stable stream; every hard gate still applies.
- Fixture-only profiles belong to fixture data, not the production profile registry.

## Delivery Gates

1. Plan-first parity: all released fixed streams compile through one pure plan, validate together, and retain output identity.
2. Fact consolidation: RecipeFactV2 and shared indexes replace parallel partial recipe models.
3. Attach-only automation: structural family rules attach safe loader, mining drill, module, logistics, furnace, lab, and power recipes to existing streams.
4. Reviewed expansion: only fixture-backed manifest-declared family emission or compatibility packs may add new behavior.

Family modules are open-ended data declarations behind one stable policy contract. Adding a family requires a manifest row, stable identity, positive and negative structural fixtures, balance and migration review, and target capability evidence; it does not require another player-facing compiler mode. Compatibility packs refine exact ecosystems but cannot mutate prototypes or weaken hard gates.

Each gate requires focused pure tests, static validation, deterministic plan evidence, a generated-ID parity check, and target runtime validation before it can become a release candidate.

`fixtures/golden-plans/stable-technology-ids.json` locks the 70 released 3.1.0 identities. `automatic-family-technology-ids.json` separately locks reviewed 3.1.0 generic-family identities. Both must pass before runtime validation; a future family technology must update its reviewed golden explicitly rather than appearing as incidental compiler output.
