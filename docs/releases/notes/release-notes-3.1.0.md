---
title: "MIR 3.1.0 Release Notes"
status: current
applies_to: "3.1.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-13
supersedes: []
superseded_by: []
---

# MIR 3.1.0 Release Notes

MIR 3.1.0 is the first automatic compatibility compiler release for Factorio 2.1. It preserves the released 3.0.5 generated technology IDs, settings/profile contract, runtime namespaces, and default behavior while replacing fixed, order-sensitive generation paths with immutable facts, data-defined family rules, whole-plan validation, and transactional emission.

## Player-Facing Changes

- Scripted research now has explicit save/load, force lifecycle, setting disable/re-enable, rebasing, and restoration coverage.
- Recycler safety handles multiple return paths, byproducts, probability, ignored productivity, catalysts, fluids, recipe variants, and conversions back to production inputs.
- The default `safe-attach` compiler mode structurally discovers module, loader, belt, mining-drill, inserter, furnace, assembling-machine, lab, solar, and storage manufacturing recipes without relying on recipe-name tokens.
- The opt-in `safe-generate` mode may also emit the two reviewed, stable generic assembling-machine and lab manufacturing technologies. It cannot create incidental per-mod or per-recipe technology IDs.
- Science and prerequisite planning share one deterministic fact model and preserve conservative skip reasons when the active labs cannot research a stream.
- Every final recipe receives an accounting outcome such as generated coverage, attachment, external ownership, safe skip, unsafe skip, target unsupported, ambiguity, or unclassified. Accounting is diagnostic evidence, not a promise that every recipe should receive productivity.
- Settings catalogs and portable profiles are isolated from mutation, preserve released values, and retain target/provider-specific values when rows are hidden.
- Release archives are byte reproducible; identical package-visible source produces identical ZIP bytes.
- Renamed the player-facing automatic-family setting to Automatic Research Coverage and added clear, capitalized option names plus a detailed tooltip for every dropdown choice. Internal setting keys and stored values are unchanged.

## Compatibility Evidence

The final Factorio 2.1 manifest contains `89` required scenarios across base, Space Age, exact ZIP loading, compiler contracts, mutation ownership, settings, recycler policy, scripted runtime behavior, compatibility ownership, and local fixtures. The release evidence binds the clean full-matrix result to the exact candidate archive. Exact 3.0.5-to-3.1.0 upgrade evidence retains non-default settings, research levels, persisted fixture state, and the active scripted multiplier.

Nine independent exact-archive scenarios currently pass for available local closures: four AAI configurations, BZ with Space Age, Bob 3.0, Krastorio 2 base, K2SO, and a complete 46-mod Space Age planet cluster. These are `loads` claims only. They do not claim complete automatic coverage, progression, balance, migration, or full-pack support. Angel, Space Exploration, and Pyanodon remain unclaimed until complete dependency closures are executed.

## Maintainer Changes

- `GenerationPlan` schema 3 uses evidence-bearing gates, rejects duplicate semantic effects, and validates final output ownership. `CompilationPlan` schema 2 now finalizes generated, adopted, and base-continuation operations together before emission and binds source, base, operation, and validation fingerprints.
- Recipe facts now resolve Factorio defaults and preserve independent/shared probability, extra-count, freshness, and quality fields before structural family decisions.
- Compatibility packs now apply exact selectors, aliases, family-scoped stream authorization, reviewed soft-risk exceptions, candidate seeds, science roles, owner claims, and deterministic precedence in production resolution. Hard safety blockers cannot be overridden.
- `RecipeFactV2` preserves recipe variants, item/fluid types, probabilities, amount ranges, catalysts, productivity exclusions, surface conditions, quality evidence, and recycling identity.
- Shared indexes replace repeated technology and entity scans; the scale gate materializes 1,000 recipes, 1,000 technologies, 10,000 effects, and 999 graph edges.
- `FamilyRule` and `CompatibilityPack` schema 2 are data-only, target-filtered, applicability-bound, and fail closed on ownership, science, lab, prerequisite, loop, or risk uncertainty.
- One effect metadata registry drives identity, numeric fields, units, display scaling, target support, settings, owner matching, and emission validation.
- Prototype mutations route through dependency-ordered pipeline transactions; policy modules remain plan-only and only emitters create generated technology prototypes.
- Runtime scenario schema 3 owns fixtures, settings, source mode, timeout, tags, isolation, and structured assertions. The harness selects by scenario, group, tag, tier, or changed path; reuses one exact package; isolates concurrent Factorio processes; records assertion execution; and emits structured failure packets.

## Upgrade

Update normally from 3.0.5. No settings or research reset is required. See the [3.1.0 migration guide](../3.1.0-migration-guide.md) for the exact compatibility boundary.
