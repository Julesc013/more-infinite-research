---
title: "2.2.0 Release Notes"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# 2.2.0 Release Notes

This is the short, player-facing release summary for the `2.2.0` GitHub and Mod Portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

`2.2.0` is a compatibility-platform release for the Factorio `2.1` line. It adds fixture-backed support for a few narrow mod surfaces, improves how MIR explains generated and rejected productivity, and keeps risky broad automation out of the release.

## Highlights

- Added Air Scrubbing clean-filter productivity for exact pollution and spore filter crafting recipes.
- MIR intentionally does not add productivity to Air Scrubbing scrubbing, cleaning, recovery, or environmental-removal recipes.
- Added ATAN Ash separation productivity for the exact ash separation recipe.
- MIR intentionally does not add productivity to ATAN Ash landfill, brick, nutrient, foundation, tile, or recovery-style ash sink recipes.
- Added ATAN-style Nuclear Science coverage through Science pack productivity when the nuclear science pack recipe and lab inputs are visible.
- Added AAI-style loader recipe coverage through Transport belt productivity.
- Added Big Mining Drill coverage through Mining drill productivity.
- Added compatibility coverage for Fluid Must Flow, Robot Attrition, Jetpack, Equipment Gantry, AAI Containers, and AAI Industry as coexistence/load-check surfaces, not new MIR-owned gameplay systems.

## Smarter Science-Pack Pressure

The `Extra science packs for generated technologies` startup setting now has progression-aware options:

- `Match Space Age progression`
- `Fill official progression`
- `Match modded progression`

These options keep the settings page compact while giving players more control over generated technology ingredients. The modded progression option follows the loaded technology graph for selected modded science packs when those packs expose normal lab inputs, unlock recipes, and prerequisite technologies. It does not blindly add every active modded science pack; `Use all lab science packs` remains the explicit broad option.

## Diagnostics And Safety

- Added typed prototype facts for recipes, technologies, machines, labs, owners, and rule surfaces.
- Added compiler decision rows for generated technologies, rejected loop risks, and observed rule surfaces.
- Added loop-risk reports for recycling, cleaning, voiding, barrel/container-return, transmutation, and self-return recipes.
- Added lab-matrix reports so generated technologies can be checked against labs that accept their science sets.
- Added useful-level estimates to recipe productivity cap reports.
- Added capability diagnostics for entity-backed loader and mining-drill crafting recipes.
- Added native modifier ownership diagnostics for selected lab, mining, logistics, and robot modifiers.

## Boundaries

This release does not add broad automatic productivity generation for unknown mods. It also does not mutate recipe caps, beacon rules, module rules, pollution or spore removal values, research costs, runtime production statistics, or external mod balance settings.

Krastorio 2 is planned as the first large overhaul campaign target after the current fixture-backed proof ladder, but `2.2.0` does not claim broad K2, Bob's, Angel's, Space Exploration, or Pyanodons support.

## Validation

The final release package should be built from `main` as:

```text
dist/more-infinite-research_2.2.0.zip
```

Use `docs/test-results.md` for the exact validation record and package hash from the final release candidate.
