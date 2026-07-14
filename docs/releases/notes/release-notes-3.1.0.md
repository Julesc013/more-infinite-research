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

MIR 3.1.0 is a compatibility, correctness, and maintainability release for Factorio 2.1. It preserves the released 3.0.5 defaults, generated technology IDs, settings/profile contract, and runtime state while making the compiler more deterministic and easier to extend safely.

## Player-Facing Changes

- Scripted research now has explicit save/load, force lifecycle, setting disable/re-enable, rebasing, and restoration coverage.
- Recycler safety handles multiple return paths, byproducts, probability, ignored productivity, catalysts, fluids, recipe variants, and conversions back to production inputs.
- Loader and mining-drill manufacturing research uses structural recipe/item/entity evidence instead of mod-name branches.
- Science and prerequisite planning share one deterministic fact model and preserve conservative skip reasons when the active labs cannot research a stream.
- Settings catalogs and portable profiles are isolated from mutation, preserve released values, and retain target/provider-specific values when rows are hidden.
- Release archives are byte reproducible; identical package-visible source produces identical ZIP bytes.

## Compatibility Evidence

The complete Factorio 2.1 matrix contains `82` passing scenarios across base, Space Age, exact ZIP loading, settings, recycler policy, scripted runtime behavior, compatibility ownership, and local fixtures. Exact 3.0.5-to-3.1.0 upgrade evidence retains non-default settings, research levels, persisted fixture state, and the active scripted multiplier.

The release-targeted local library contains `594` archives. The BZ Space Age suite, Big Mining Drill/Biolabs smokes, and K2SO load observation passed. K2SO remains load/performance evidence rather than a broad support claim; MIR intentionally skips streams that its overhaul lab graph cannot research.

## Maintainer Changes

- Canonical typed stream descriptors own effect, settings, target, science, ordering, fixture, and migration metadata.
- One immutable recipe-fact authority supplies supported planners and diagnostics with scan-count enforcement.
- Prototype mutations route through named target-positive commands; only emitters create generated technology prototypes.
- Validation now uses reusable process, settings-override, scenario-registry, package-identity, target-profile, grouping, and result modules while preserving its CLI and schema-2 evidence.
- Declared performance budgets cover base, Space Age, caps, diagnostics, local packs, the synthetic graph, and the full matrix.

## Upgrade

Update normally from 3.0.5. No settings or research reset is required. See the [3.1.0 migration guide](../3.1.0-migration-guide.md) for the exact compatibility boundary.
