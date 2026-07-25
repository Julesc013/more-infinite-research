---
title: "MIR 3.2.0 Release Notes"
status: current
applies_to: "3.2.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-25
supersedes: []
superseded_by: []
---

# MIR 3.2.0 Release Notes

MIR 3.2.0 is a major compiler, compatibility, and technology expansion for Factorio 2.1.11 and newer.

## New technologies

- Added Steel plate productivity to Base games. Space Age continues to use its native steel productivity technology as the sole owner.
- Added Nutrients productivity at `+10%` per level for the exact yumako mash, bioflux, and biter egg production recipes.
- Added Capture bot rocket productivity at `+10%` per level.
- Extended Landfill productivity with ice platforms at `+2%` and space platform foundations at `+1%` per level.
- Retained landfill at `+10%` and foundation at `+5%` per level.
- Included pentapod eggs in Breeding productivity while preserving the productivity-exempt seed egg.
- Extended the established robot follower-count research into infinite continuation levels.

## Settings and defaults

- Enabled all established MIR technology toggles by default.
- Spoilage preservation and inserter capacity remain classified as factory-disruptive even though they now default on.
- Risky technologies sort in the first settings attention group.
- Risky enable settings and technology tooltips automatically include localized factory-impact warnings.
- Kept broad automatic recipe-family creation experimental and disabled by default.
- Preserved existing public setting IDs, generated technology IDs, migrations, and runtime storage namespaces.

## Compatibility fixes

- Fixed Space Exploration plus Krastorio 2 startup failure when Space Exploration removes `kr-copper-cable-from-copper-ore`.
- Fixed technologies retaining recipe effects for recipes removed by another mod, including Pyanodon-style replacement and removal cases.
- Added target-aware cleanup for invalid recipe, item, quality, space-location, ammunition-category, and entity references.
- Preserved valid planet discovery effects and quality-specific item grants during cleanup.
- Fixed recognized competing productivity owners being skipped by a shadowed eligibility variable.
- Corrected prerequisite rewiring after competing technologies are replaced or removed.
- Preserved K2SO advanced-circuit progression through automation, logistic, chemical, production, and electromagnetic science.

## Compiler and safety overhaul

- Rebuilt technology generation around immutable compiler inputs, explicit candidate designs, safety qualifications, transformation plans, and postconditions.
- Added stable compiler contracts for ownership, recipe targets, science, prerequisites, lifecycle, settings, and final emission.
- Validated the combined existing and planned technology graph before emission using iterative strongly connected components.
- Requalified the realized graph after any competing-technology replacement or prerequisite rewrite.
- Recorded every replacement and dependent prerequisite change in a fingerprinted mutation journal.
- Added fail-closed target-integrity checks before publishing generated technologies or compiler data.
- Replaced whole-prototype continuation cloning with an allowlisted builder.
- Moved all generated-technology mutation behind the emission-owned executor.
- Added deterministic ordering, output fingerprints, mutation journals, diagnostics, and bounded compiler telemetry.
- Reduced repeated validation, copying, fingerprinting, and catalog serialization without weakening final validation.

## Native technology ownership

- Added exact native-owner handling for low-density structures, plastic, processing units, rocket fuel, and Space Age steel productivity.
- MIR settings now update recognized native productivity technologies without duplicating their recipe ownership.
- Disabling a stream leaves an external owner untouched.
- Cost and effect changes preserve recognized native formula styles and reject unsafe unknown models.
- Existing research level and fractional progress are preserved across supported configuration changes.

## Packaging and release assurance

- Added deterministic package construction and exact ZIP composition checks.
- Added content-addressed scenario evidence with strict candidate, binary, mod closure, settings, fixture, and harness fingerprints.
- Added explicit Base, Space Age, K2SO, BZ, upgrade, ecosystem, performance, and compatibility scenario contracts.
- Added portable museum validation for Factorio 0.12 through 0.6 without requiring historical installations on hosted CI.
- Kept repository documentation, fixtures, scripts, tests, manifests, build output, and evidence out of the release ZIP.

## Exact release artifact

- File: `more-infinite-research_3.2.0.zip`
- Size: `1,029,464` bytes
- Entries: `290`
- SHA-256: `35372EE6D16DA6765E8C30AEAAF5DA4A5D300F02C0A0A03648C80893A5394F32`
- Package-source commit: `303de261629149af5f50bd210368e61423f1a299`

Publish the recorded ZIP without rebuilding it, and verify downloaded copies against the SHA-256 above.
