---
title: "FamilyRule Schema"
status: current
applies_to: "post-3.1 dev"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# FamilyRule Schema

A schema-1 `FamilyRule` is inert data consumed by the semantic family resolver. It cannot contain functions, prototype tables, mod names, version gates, or mutation callbacks.

Required fields are a stable `id`, `capability`, and `mode`. `attach-existing` rules also declare a released `target_stream` plus structural selectors and a conservative effect change. `proposal-only` rules explain a structurally recognized family that has no safe released stream.

The initial selectors are entity types reached through item `place_result` relationships and item prototype types such as modules. Recipe names are evidence labels, not classification inputs.

Before attachment, the resolver rejects hidden, parameterized, recycling, self-returning, productivity-disabled, zero-cap, and externally owned recipes. An attachment may only add an effect to an existing stable stream. It cannot create a technology, technology ID, setting, or migration record.

For placeable-item families, every recipe variant must also have one deterministic item result: the structurally matched placeable item. Probability, range, shared-probability, catalyst, ignored-productivity, and extra-output shapes fail closed.

The initial attach-only rules cover structurally proven loaders and belts, mining drills, furnaces, inserters, accumulators and solar panels, and module tiers. Assembling-machine and lab manufacturing target separately reviewed stable generic-family streams; those streams emit only in `safe-generate` or exact-pack mode.
