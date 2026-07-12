---
title: "MIR 3.1.0 Release Notes"
status: current
applies_to: "3.1.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-12
supersedes: []
superseded_by: []
---

# MIR 3.1.0 Release Notes

MIR 3.1.0 is the first plan-first automatic compatibility compiler release for Factorio 2.1. It preserves the released 3.0.5 generated technology IDs, settings/profile contract, runtime namespaces, and default behavior while replacing fixed, order-sensitive generation paths with immutable facts, data-defined family rules, whole-plan validation, and transactional emission.

## Player-Facing Changes

- Scripted research now has explicit save/load, force lifecycle, setting disable/re-enable, rebasing, and restoration coverage.
- Recycler safety handles multiple return paths, byproducts, probability, ignored productivity, catalysts, fluids, recipe variants, and conversions back to production inputs.
- The default `safe-attach` compiler mode structurally discovers module, loader, belt, mining-drill, inserter, furnace, assembling-machine, lab, solar, and storage manufacturing recipes without relying on recipe-name tokens.
- The opt-in `safe-generate` mode may also emit the two reviewed, stable generic assembling-machine and lab manufacturing technologies. It cannot create incidental per-mod or per-recipe technology IDs.
- Science and prerequisite planning share one deterministic fact model and preserve conservative skip reasons when the active labs cannot research a stream.
- Every final recipe receives an accounting outcome such as generated coverage, attachment, external ownership, safe skip, unsafe skip, target unsupported, ambiguity, or unclassified. Accounting is diagnostic evidence, not a promise that every recipe should receive productivity.
- Settings catalogs and portable profiles are isolated from mutation, preserve released values, and retain target/provider-specific values when rows are hidden.
- Release archives are byte reproducible; identical package-visible source produces identical ZIP bytes.

## Compatibility Evidence

The current exact-source Factorio 2.1 matrix contains `86` passing scenarios across base, Space Age, exact ZIP loading, compiler contracts, mutation ownership, settings, recycler policy, scripted runtime behavior, compatibility ownership, and local fixtures. Exact 3.0.5-to-3.1.0 upgrade evidence retains non-default settings, research levels, persisted fixture state, and the active scripted multiplier.

Eight independent exact-archive scenarios currently pass for available local closures: four AAI configurations, BZ with Space Age, Bob 3.0, Krastorio 2 base, and K2SO. These are `loads` claims only. They do not claim complete automatic coverage, progression, balance, migration, or full-pack support. Angel, Space Exploration, Pyanodon, and representative planet campaigns remain unclaimed until complete dependency closures are executed.

## Maintainer Changes

- `GenerationPlan` schema 2 validates all fixed and automatic streams as one deterministic set before emission.
- `RecipeFactV2` preserves recipe variants, item/fluid types, probabilities, amount ranges, catalysts, productivity exclusions, surface conditions, quality evidence, and recycling identity.
- Shared indexes replace repeated technology and entity scans; the scale gate materializes 1,000 recipes, 1,000 technologies, 10,000 effects, and 999 graph edges.
- `FamilyRule` and `CompatibilityPack` schema 2 are data-only, target-filtered, applicability-bound, and fail closed on ownership, science, lab, prerequisite, loop, or risk uncertainty.
- One effect metadata registry drives identity, numeric fields, units, display scaling, target support, settings, owner matching, and emission validation.
- Prototype mutations route through dependency-ordered pipeline transactions; policy modules remain plan-only and only emitters create generated technology prototypes.
- Scenario schema 2 owns setup, target, roots, settings, expected plan boundary, timeout, and claim level. Planner snapshot, diff, minimization, target comparison, and review-required pack-scaffolding tools are deterministic and schema-bound.

## Upgrade

Update normally from 3.0.5. No settings or research reset is required. See the [3.1.0 migration guide](../3.1.0-migration-guide.md) for the exact compatibility boundary.
