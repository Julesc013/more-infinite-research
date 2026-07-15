---
title: "CompilerProvider Schema"
status: current
applies_to: "3.1.5+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# CompilerProvider Schema

`CompilerProvider` schema 1 is MIR's stable, data-only extension contract for automatic productivity families. Providers describe how final prototype facts become normalized family candidates. They do not inspect mod names, mutate prototypes, or bypass planner gates.

Every provider declares:

- a globally stable `id`, supported `source_kinds`, family, discovery indexes, normalization rule, and optional semantic-signature descriptor;
- positive capabilities and a fail-closed default policy;
- setting and localization descriptor references;
- validation hooks, a planning-only emission adapter, and whether a separately registered runtime handler is required;
- migration identity, stable diagnostic codes, fixtures, and the FamilyRule consumed by the current planner adapter.

The registry rejects missing fields, behavioral callbacks, direct Factorio-global references, duplicate IDs, mutating emission adapters, unregistered runtime requirements, and provider/family identity mismatches. It sorts by provider ID before fingerprinting or exposing snapshots, and every snapshot is a deep copy. Registration order therefore cannot change a plan.

Built-in providers are ordinary schema-1 rows. A future provider can add a source or family without editing the discovery, settings, policy, planning, or emission cores, provided its capabilities and fixtures satisfy the same contract.

## Stage Ownership

The provider surface fits the compiler pipeline as follows:

1. discovery reads final prototype fact indexes;
2. normalization creates stable source and semantic identity;
3. capability classification and policy decide whether a candidate proceeds;
4. FamilyRule planning resolves stream ownership and effects;
5. graph validation checks science, prerequisites, progression, cycles, and identity;
6. only `prototypes/mir/emit` materializes accepted plans;
7. structured diagnostics retain provider ID, source key, identity seed, target support, evidence, and final state.

Compatibility packs may refine provider decisions with exact evidence, but cannot create providers, cross-mutate their candidates, or override hard safety facts.
