---
title: "FamilyRule Schema"
status: current
applies_to: "3.1.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# FamilyRule Schema

A schema-2 `FamilyRule` is inert data consumed by the semantic family resolver. It cannot contain functions, prototype tables, mod names, version gates, or mutation callbacks. Its executable classification contract is a schema-1 [Family Operator DSL](family-operator-dsl.md) record composed from a finite registered library.

Every rule owns a stable ID, CompilerProvider ID, family and capability, structural output selector, required evidence, hard recipe requirements, risk denials, grouping and tier strategies, effect table, exact-owner policy, science and prerequisite strategy, positive target features, default action, and support-claim boundary. The registry rejects missing provider identity, duplicate IDs, incomplete hard requirements, missing core risk denials, non-structural selectors, missing effect policy, non-positive target requirements, or a public structural claim.

The initial selectors are entity types reached through item `place_result` relationships and item prototype types such as modules. Recipe names are evidence labels, not classification inputs. All rules require RecipeFactV2 plus shared place-result and effect-owner indexes. Legacy selector, tier, and effect fields remain compatibility data during the 3.2 transition; the resolver does not dispatch them.

Before attachment, declared gates reject hidden, parameterized, recycling, self-returning, productivity-disabled, zero-cap, non-deterministic, and externally owned recipes. An attachment may only add an effect to an existing stable or predeclared reviewed stream. It cannot allocate a technology, setting, or migration identity.

For placeable-item families, every recipe variant must have one deterministic item result: the structurally matched placeable item. Probability, range, shared probability, catalyst, ignored-productivity, and extra-output shapes fail closed.

The initial rules cover structurally proven loaders and belts, mining drills, furnaces, inserters, accumulators and solar panels, and module tiers. Assembling-machine and lab manufacturing target separately reviewed stable generic-family streams; those streams emit only in `safe-generate` or exact-pack mode.
