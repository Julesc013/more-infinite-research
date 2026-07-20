---
title: "MIR 2.4.9 Release Notes"
status: current
applies_to: "2.4.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# MIR 2.4.9 Release Notes

MIR 2.4.9 is a stability, compatibility, localization, and performance backport for Factorio 2.0. It carries the mature fixes from ongoing MIR development into the maintained 2.4 release line without enabling the experimental automatic technology families.

## Highlights

- Added infinite steel-plate productivity to the base game, matching MIR's established iron, copper, tungsten, sulfur, and other productivity families.
- Integrated safely with Space Age's native `steel-plate-productivity` research instead of creating a duplicate technology.
- Fixed the Space Exploration and Krastorio startup failure caused by a technology trying to unlock the removed `kr-copper-cable-from-copper-ore` recipe.
- Completed and synchronized locale files for all 50 languages supported by Factorio.
- Preserved existing saves, settings, research identifiers, research progress, and runtime data from MIR 2.4.5.

## Added

- Added a stable steel-productivity research stream for valid recipes that produce steel plate.
- Added safe adoption of compatible steel recipes, including Space Age steel casting, under the existing native productivity owner.
- Added complete locale coverage for every Factorio language, including completed Simplified and Traditional Chinese translations.
- Added automated locale checks for missing or stale strings, placeholders, rich text, compact UI labels, empty values, and formatting regressions.
- Added stronger validation for recipe, item, quality, space-location, ammo-category, and turret targets referenced by technology effects.
- Added exact upgrade, ecosystem, deterministic-package, performance, and compatibility regression coverage for the 2.4 release line.

## Fixed

- Fixed startup crashes when another mod removes a recipe after MIR has selected it for a technology unlock.
- Fixed the Space Exploration/Krastorio copper-cable compatibility failure while retaining the technology and all of its remaining valid effects.
- Fixed dangling `unlock-recipe`, `unlock-quality`, `unlock-space-location`, `give-item`, `ammo-damage`, `gun-speed`, and `turret-attack` targets.
- Fixed `give-item` effects for the same item at different quality levels being treated as duplicates.
- Fixed unsupported `mod-data` prototype output being emitted by the Factorio 2.0 package.
- Fixed steel, iron, and copper productivity families incorrectly considering scrap-recovery recipes, preventing circular material-productivity loops.
- Fixed possible cross-mod side effects during configuration changes by no longer resetting every force's technology effects.
- Fixed potential duplication of researched `give-item` rewards during MIR configuration changes.
- Fixed preservation risks for recipe availability and force-level changes made by Factorio or other mods.

## Changed

- MIR now removes only invalid technology effects and preserves every valid effect in its original order.
- Base Factorio uses MIR's steel-productivity technology, while Space Age continues to use its native technology as the single owner.
- Productivity ownership and adoption are now deterministic across base-game, Space Age, and mixed mod configurations.
- Release packages are now built deterministically and checked against their exact source, contents, upgrade baseline, and approved change set.
- Validation and performance evidence are now fingerprinted so results are reused only when all relevant inputs are identical.
- The verification system now isolates scenario workers and combines their results through one final release gate.

## Removed

- Removed MIR's explicit global `reset_technology_effects()` call during configuration changes.
- Removed invalid technology effects that point to prototypes deleted by the final mod set.
- Removed unsupported Factorio 2.1-only `mod-data` behavior from the Factorio 2.0 build.
- Removed duplicate ownership of Space Age steel productivity.

## Compatibility and upgrade notes

- Existing MIR 2.4.5 saves can upgrade directly to 2.4.9.
- Existing settings, generated technology IDs, migrations, research selection, research level, fractional progress, and MIR runtime namespaces are preserved.
- No new experimental automatic research families are enabled by default.
- The Space Exploration/Krastorio fix is exact and targeted; this release does not claim complete support for every combination of those mod suites.
- Broad Pyanodon support is not claimed, although MIR's generic integrity repairs are safer for modded technology trees.

## Validation

- Passed 106 machine-verifiable release checks and 92 Factorio runtime scenarios.
- Passed exact base-game, Space Age, upgrade, ecosystem, localization, package, and removed-recipe regression tests.
- Passed a paired six-lane 2.4.5-versus-2.4.9 performance campaign with five measured runs per package in every lane.
- The largest measured median regression was 6.42% with diagnostics enabled; all performance lanes remained within their release limits.
