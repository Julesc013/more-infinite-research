---
title: "Automatic Family Compiler"
status: current
applies_to: "2.4.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# Automatic Family Compiler

MIR 3.1.0 is the immutable released behavior baseline. Development after that release turns its fixed declarative stream compiler into a plan-first semantic family compiler. This work originates on `dev`; it does not rebuild, retag, or change the published 3.1.0 archive.

## Pipeline Contract

```text
final prototype state
-> RecipeFactV2 and shared indexes
-> data-only FamilyRule registry
-> capability candidates and decisions
-> pure GenerationPlan
-> whole-plan validation
-> emission
-> diagnostics and golden-plan evidence
```

Planning is side-effect free. Only modules under `prototypes/mir/emit/` may create or mutate generated technology prototypes. Reporting materializes decisions; it is not an alternative mutation path.

`GenerationPlan` is the common intermediate representation for every fixed and automatic stream. Schema 2 records stable stream identity, technology identity, effects, science, prerequisites, cost, migration policy, evidence, blockers, risks, source provenance, explicit proof gates, source fingerprints, and a deterministic plan fingerprint. All plan rows are validated as one set before the first generated prototype is emitted.

`DecisionRecordV2` keeps typed evidence classes instead of treating a formatted confidence string as authority. Confidence ranks review evidence; hard safety gates remain independent booleans and cannot be averaged into an emission decision.

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

`fixtures/golden-plans/stable-technology-ids.json` locks the 70 released 3.1.0 identities. `automatic-family-technology-ids.json` separately locks reviewed 3.2.0 generic-family identities. Both must pass before runtime validation; a future family technology must update its reviewed golden explicitly rather than appearing as incidental compiler output.
