---
title: "Automatic Family Compiler"
status: current
applies_to: "3.1.0 dev"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# Automatic Family Compiler

MIR 3.0.5 is the published immutable behavior baseline. MIR 3.1.0 turns its fixed declarative stream compiler into a plan-first semantic family compiler on `dev`. Earlier 3.1.0 candidate artifacts and tags are superseded development evidence, not published release authority.

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

`GenerationPlan` is the common intermediate representation for every fixed and automatic stream. Schema 3 records stable stream identity, technology identity, effects, science, prerequisites, cost, migration policy, evidence, blockers, risks, source provenance, evidence-bearing proof gates, source fingerprints, and a deterministic plan fingerprint. The compilation-plan envelope adds prevalidated base-extension operations. All rows and operations are validated before the first generated prototype is emitted, and final output parity is asserted after mutation.

`DecisionRecordV2` keeps typed evidence classes instead of treating a formatted confidence string as authority. Confidence ranks review evidence; hard safety gates remain independent pass/fail records and cannot be averaged into an emission decision.

## Compatibility And Identity Boundary

- Preserve all 70 released stream and technology IDs.
- First automatic behavior is attach-only: high-confidence recipes may join an existing stable stream. It creates no per-recipe technology IDs.
- Predeclared family technologies require an explicit manifest row and migration review before emission is enabled.
- Ambiguous, risky, loop-forming, hidden, or externally owned candidates remain proposal-only or diagnostic-only.
- Compatibility packs contain selectors, policy, expected decisions, and claim metadata. They do not read `data.raw` or mutate prototypes.
- Fixture-only profiles belong to fixture data, not the production profile registry.

## Delivery Gates

1. Plan-first parity: all released fixed streams compile through one pure plan, validate together, and retain output identity.
2. Fact consolidation: RecipeFactV2 and shared indexes replace parallel partial recipe models.
3. Attach-only automation: structural family rules attach safe loader, mining drill, module, logistics, furnace, lab, and power recipes to existing streams.
4. Reviewed expansion: only fixture-backed manifest-declared family emission or compatibility packs may add new behavior.

Each gate requires focused pure tests, static validation, deterministic plan evidence, a generated-ID parity check, and target runtime validation before it can become a release candidate.

`fixtures/golden-plans/stable-technology-ids.json` locks the 70 released 3.1.0 identities. `automatic-family-technology-ids.json` separately locks reviewed 3.1.0 generic-family identities. Both must pass before runtime validation; a future family technology must update its reviewed golden explicitly rather than appearing as incidental compiler output.
