---
title: "More Infinite Research 1.9.3 Release Notes"
status: archived
applies_to: "1.1"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.9.3 Release Notes

`1.9.3` is the Factorio `1.1` compatibility port of the MIR 3 compatibility
compiler architecture.

It is not a feature-parity backport of the Factorio `2.0` or `2.1` releases.
It keeps the architecture where Factorio `1.1` can support it and removes
Factorio `2.x` surfaces before they can emit invalid prototypes.

## What Changed

- Retargeted package metadata to `version = "1.9.3"`,
  `factorio_version = "1.1"`, and `base >= 1.1`.
- Removed Space Age, Quality, Recycler, Elevated Rails, cargo logistics,
  spoilage, agriculture, and recipe-productivity streams from the `1.1`
  target line.
- Added a target-line adapter that disables unsupported streams, direct
  effects, compatibility repairs, prototype limits, pipeline extent changes,
  and runtime handlers before generation.
- Replaced direct runtime persistence access with a state adapter that uses
  `global` on Factorio `1.1` and `storage` on Factorio `2.x`.
- Retargeted branch-local support mod metadata to Factorio `1.1`.
- Hid settings-profile import/export on the `1.1` line because Factorio `1.1`
  does not expose the `helpers` string codec API used by MIRSET1 profiles.
- Replaced newer `__core__/graphics/icons/technology/constants/*` badge
  overlays on the `1.1` line with target-era base technology badge fallbacks
  instead of bundling newer Factorio graphics.

## Supported Surface

- Direct-effect infinite researches that loaded in the Factorio `1.1` binary:
  weapon shooting speed, cannon shooting speed, rocket shooting speed,
  electric shooting speed, flamethrower shooting speed, character crafting,
  character mining, character reach, character walking speed, character
  inventory/trash-slot capacity, lab productivity, and worker robot battery.
- Vanilla finite-chain continuations for supported base technologies such as
  braking force, lab research speed, laser shooting speed, weapon shooting
  speed, worker robot cargo size, and opt-in inserter capacity.
- Startup settings for supported streams and base continuations.

## Compatibility Checks

- Static validation passed for the `1.9.3` metadata and package shape.
- Factorio `1.1` binary validation passed with `D:\Programs\Factorio\1.1\bin\x64\factorio.exe`.
- The runtime gate loaded the packaged zip and ran the reduced `1.1` scenarios:
  direct effects, lab productivity owner skip, robot battery owner skip,
  merged inventory/trash capacity, settings surface, checkbox enable/disable,
  and weapon-speed overlap safety.
- The `factorio-1.1-direct-effects` runtime scenario now asserts every
  supported generated direct-effect technology has a target-era effect badge
  and no newer core constant icon path.
- A disposable Factorio `1.1.110` proof mod using
  `change-recipe-productivity` failed to load with `Unknown modifier type`,
  confirming recipe productivity streams are an engine-surface exclusion on
  the `1.1` line.

## Known Boundaries

- Recipe productivity is not included in this Factorio `1.1` compatibility
  port because the target binary rejects `change-recipe-productivity`.
- Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage,
  agriculture, prototype cap settings, pipeline extent settings, and settings
  profiles are not included on the `1.1` line.
- Newer Factorio core graphics are not bundled into the `1.1` package; MIR
  falls back to icons available in the target install.
- Compatibility docs should describe this release as a reduced compatibility
  port generated from the MIR 3 architecture, not as identical to `2.3.0` or
  `3.0.0`.
