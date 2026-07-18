---
title: "Family Operator DSL"
status: current
applies_to: "3.2.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# Family Operator DSL

The schema-1 Family Operator DSL is the executable data contract for automatic family classification. `prototypes/mir/families/operator_dsl.lua` owns the finite operator registry, validation, and interpretation. Providers compose descriptors; they cannot supply callbacks, prototype tables, unregistered operators, or mutation instructions.

Every record declares selectors and normalizers plus one partitioner, tier resolver, effect model, science model, prerequisite model, cost model, presentation model, ownership policy, and grouping decision. The initial library supports structural recipe facts, deterministic place-result relationships, prototype module tiers, fixed or tier-table effects, inherited reviewed stream policy, exact-owner preference, existing-stream attachment, and proposal-only grouping.

The family registry validates a record once before resolution. Resolver execution uses only the registered DSL operators. Adding a family should therefore require provider data, reviewed examples and counterexamples, applicability policy, and fixtures; it should not require a new resolver branch.

Names are not structural selectors. Recipe and prototype names may appear in evidence and exact reviewed policy, but generic classification prioritizes prototype type, place result, normalized recipe shape, tier facts, ownership, and hard risk gates.

Hard safety remains outside reviewable policy. Productivity-disabled, zero-cap, non-deterministic, recycling, self-return, missing-target, and conflicting-owner facts fail closed regardless of an operator composition or CompatibilityPack hint.
