---
title: "More Infinite Research 1.9.2 Release Notes"
status: archived
applies_to: "1.x-2.x"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.9.2 Release Notes

This is the short, player-facing release summary for the `1.9.2` legacy release notes. It is derived from `changelog.txt`; the changelog remains the detailed source of truth.

## Headline

`1.9.2` is the Factorio `2.0` compatibility port of the tested More Infinite Research `2.2.0` source snapshot.

## What Changed

- Updated legacy metadata to `factorio_version = "2.0"` with `base >= 2.0`.
- Kept Quality as a hidden optional dependency and Space Age as an optional dependency without Factorio `2.1` dependency floors.
- Backported the `2.2.0` compatibility planner foundations where they are compatible with Factorio `2.0`.
- Added compatible Air Scrubbing clean-filter productivity support for the exact pollution and spore filter crafting recipes.
- Added compatible ATAN Ash separation productivity support for the exact ash separation recipe.
- Added compatible ATAN-style Nuclear Science coverage through Science pack productivity when the nuclear science pack recipe and lab inputs are visible.
- Added compatible AAI-style loader recipe coverage through Transport belt productivity.
- Added compatible Big Mining Drill coverage through Mining drill productivity.
- Added progression-aware official and modded science-pack ingredient policies.

## Legacy Exclusions

- Factorio `2.1` cargo landing pad count and cargo bay unloading distance research are not included in this legacy release.
- MIR still does not add productivity to Air Scrubbing scrubbing, cleaning, recovery, or environmental-removal recipes.
- MIR still does not add productivity to ATAN Ash landfill, brick, nutrient, foundation, tile, or recovery-style ash sink recipes.
- Broad automatic productivity generation for unknown mods remains outside this release.

## Known Notes

- Recipe productivity still respects Factorio's normal productivity cap.
- Spoilage Preservation and Agricultural Growth Speed remain disabled by default and should be treated as experimental.
- Krastorio 2 remains a future large-overhaul campaign target; this legacy release does not claim broad K2, Bob's, Angel's, Space Exploration, or Pyanodons support.
