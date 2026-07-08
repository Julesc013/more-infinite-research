---
title: "More Infinite Research 3.0.0 Release Notes"
status: current
applies_to: "3.0.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: []
---
# More Infinite Research 3.0.0 Release Notes

This is the short, player-facing release summary for the `3.0.0` GitHub and Mod Portal release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

`3.0.0` is the MIR compatibility compiler architecture release for the Factorio `2.1` line. It keeps generated technology IDs stable, moves active implementation into the MIR compiler namespace, and makes compatibility behavior more explicit and easier to audit.

This release is not a broad new gameplay-content wave. It is the release that turns the existing compatibility work into a cleaner, stricter foundation for future MIR releases.

## Highlights

- Existing generated technology IDs are preserved.
- No new migration is required solely because of the `3.0.0` architecture move.
- Existing `2.0.5` and `2.1.0` migrations remain shipped.
- Space Age remains optional.
- Quality, Recycler, and Elevated Rails remain optional or hidden optional dependencies as recorded in `info.json`.
- Generated research is still created only when the needed recipes, technologies, ammo categories, labs, and science packs are available.
- Unsafe, missing, or unresearchable research candidates are skipped or kept diagnostic-only instead of being forced into invalid mod sets.
- Recipe productivity research is still infinite, but Factorio's normal recipe productivity cap still applies.
- Scripted spoilage preservation and agricultural growth speed remain disabled-by-default experimental options.

## Compatibility

- Air Scrubbing support remains limited to exact clean-filter recipe families.
- MIR intentionally does not add productivity to Air Scrubbing scrubbing, cleaning, recovery, or environmental-removal recipes.
- ATAN Ash support remains limited to the exact ash separation recipe family.
- MIR intentionally does not add productivity to ATAN Ash landfill, brick, nutrient, foundation, tile, or recovery-style ash sink recipes.
- AAI-style loader crafting recipes are routed through Transport belt productivity when the required recipes and entities are visible.
- Standalone big mining drill recipes are routed through Mining drill productivity when the required recipes and entities are visible.
- ATAN-style Nuclear Science packs are routed through Science pack productivity when the nuclear science pack recipe and lab inputs are visible.
- Fluid Must Flow, Robot Attrition, Jetpack, Equipment Gantry, AAI Containers, and AAI Industry remain scoped to recorded coexistence or diagnostic evidence.

## Compatibility Boundaries

- This release does not claim full support for every overhaul.
- Compatibility claims remain narrow and evidence-backed.
- Compatibility policy overlays describe selectors, claims, denials, and policy data.
- Compatibility policy overlays do not directly create or mutate generated technology prototypes.
- MIR continues to prefer skipping unsafe candidates over silently generating broken or duplicated research.

## Architecture And Refactor

- Active shipped implementation now lives under `prototypes/mir`.
- Required Factorio root lifecycle files are thin wrappers over MIR stage modules.
- `prototypes/streams` remains the declarative stream-data location.
- Generated technology emission now routes through `StreamSpec` adapters and the MIR technology builder.
- Base technology continuations now route through the MIR emit layer.
- Effect safety, generated icon construction, max-level handling, and weapon-speed cleanup now route through focused MIR modules.
- Settings are built through the MIR settings stage builder instead of the old large root settings file.
- Runtime scripted technology handlers now live under `prototypes/mir/runtime`.
- Runtime code stays separate from prototype generation.

## Removed Old Paths

- Removed the old `prototypes/compat/air-scrubbing.lua` shipped implementation path.
- Removed the old `prototypes/tech-gen.lua` root generator path.
- Removed the old `prototypes/max-level-control.lua` root helper path.
- Removed the old `prototypes/planner/generated-stream-manifest.json` manifest location.
- Removed shipped runtime module paths from the old `control` folder.
- Removed active shipped ownership from broad `prototypes/lib` helper roots.
- Removed broad root helper ownership for defaults, config, diagnostics, settings resolution, pipeline extent, utilities, effect safety, cleanup, and weapon speed.
- Removed direct prototype mutation responsibility from compatibility overlays.

## Developer Notes

- Added MIR governance manifests for docs, branch policy, module boundaries, streams, compatibility claims, sample mods, settings, capabilities, and agent routing.
- Added generated stream manifest coverage for every emitted stable stream.
- Added a MIR compatibility claim registry.
- Added MIR domain records for `DecisionRecord` and `StreamSpec`.
- Added a Factorio `data.raw` adapter so prototype reads and prototype writes stay behind narrow boundaries.
- Added focused MIR index, planner, capability, policy, emit, report, compatibility, settings, and runtime modules.
- Added architecture, docs governance, settings visibility, package hygiene, claim, and policy checks.
- Added release evidence docs for the MIR 3 summary, checklist, migration guide, local library gate, regression baseline, risk register, and publish candidate.
- Added package hygiene checks to keep docs, scripts, sample mods, tests, build output, distribution output, `.mir`, `.codex`, `.github`, `AGENTS.md`, `CONTRIBUTING.md`, and the root work ledger out of release archives.

## Release Checks

- Static checks passed for docs governance, MIR manifests, architecture boundaries, settings visibility, policy linting, claim linting, changelog syntax, and package hygiene.
- Runtime sample-mod checks passed on the target Factorio `2.1` binary.
- The targeted local `2.1` mod-library gate passed.
- The final package contains `114` entries and zero forbidden repository-only paths.
- Strict audit, repair, and representative local scenario lanes stayed row-count and hash stable against the recorded `2.2` comparison lanes.

## Known Notes

- Portal-backed full-catalog checks were not run in the release environment because `FACTORIO_TOKEN` was not set.
- Local supported-zip isolation found `atan-ash_2.2.1` failing without MIR on the tested Factorio `2.1` setup.
- Local supported-zip isolation found `atan-nuclear-science_0.3.3` failing without MIR on the tested Factorio `2.1` setup.
- Those supported-zip failures are tracked as upstream package or schema issues, not MIR regressions.
