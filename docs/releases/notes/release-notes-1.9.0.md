---
title: "More Infinite Research 1.9.0 Release Notes"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.9.0 Release Notes

This is the short, player-facing release summary for the `1.9.0` Factorio `2.0` legacy release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`1.9.0` is the Factorio `2.0` legacy backport of the tested More Infinite Research `2.0.5` codebase.

This release brings the current generator, settings, diagnostics, compatibility, recipe matching, custom science-pack handling, custom lab handling, and validation work back to Factorio `2.0`.

## What This Release Is

- A Factorio `2.0` compatible legacy release.
- Based on the tested `2.0.5` current-line source snapshot.
- Intended for players staying on Factorio `2.0.x`.
- Not a commit-by-commit rebuild of older `1.x` releases.

## What Changed Since The Older 1.x Line

- Better generated recipe-productivity coverage.
- Better handling for custom science packs and custom labs.
- Better science-pack policy settings.
- Better lab compatibility behavior for generated technologies.
- Better recipe matching for modded production chains.
- Better diagnostics for generated technologies and recipe matches.
- Better startup setting names, descriptions, ordering, and warnings.
- Better technology icons and effect badges.
- Better compatibility checks for overlapping infinite technologies from other mods.
- The current package validation and runtime fixture validation infrastructure is now part of the legacy line.

## Backported 2.0.5 Fixes

- Electric Shooting Speed covers electric weapons and Space Age Tesla weapons when available.
- Electric, Tesla, and flamethrower shooting-speed effects have proper descriptions.
- Weapon-speed overlap handling preserves finite vanilla tank cannon speed bonuses.
- Quality is a hidden optional load-order dependency, so Module productivity can see Quality module recipes when Quality is active.
- Mining drill productivity covers Omega Drill style recipes such as `omega-drill` and `omega-tau`, plus broader visible modded drill recipes.
- Space Age vanilla productivity technologies stay authoritative for processing units, low density structures, plastic, rocket fuel, and research productivity where they exist.
- Character inventory slots now also grants character logistic trash slots.
- Existing progress from the old generated trash-slot technology migrates into the combined inventory/trash technology.
- Base-game Research productivity can generate when Space Age's vanilla `research-productivity` chain is absent.
- Cannon shell productivity uses clearer player-facing naming and covers cannon shells, artillery shells, railgun ammo, and compatible modded shell/ammo recipes.

## Legacy Differences From 2.0.5

The Factorio `2.0` legacy package intentionally excludes known Factorio `2.1` cargo modifier streams:

- Cargo bay unloading distance.
- Cargo landing pad count.

Those technologies remain current-line `2.x` features only.

## Experimental Candidates

`1.9.0` keeps the default-off scripted Space Age candidates from `2.0.5`:

- Spoilage Preservation.
- Agricultural Growth Speed.

They are opt-in for testing. They are not enabled by default, and stronger gameplay claims still need manual validation for existing spoilable stacks, existing farms, reversal, disabling, multi-force behavior, and larger real saves.

## Validation

This release was validated against Factorio `2.0.77`.

Validated checks include:

- Static/package validation.
- Runtime fixture validation on Factorio `2.0.77`.
- Branch-policy validation.
- Base-only release-zip smoke test.
- Space Age release-zip smoke test.
- Basic old-save smoke: a base-only `1.2.9` save loaded headlessly under `1.9.0`.

The old-save smoke proves basic save loading. A real save with old trash-slot research progress is still the best manual check for that specific migration path.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Factorio `2.1` cargo logistics technologies are not included in this legacy package.
- Scripted spoilage/agriculture research remains disabled by default.
- Real settings presets are still planned for a later current-line release.
