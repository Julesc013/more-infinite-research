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
compiler architecture. It is built from the `3.0.0` source anchor plus the
portable branch-policy, validation, package-hygiene, and documentation lessons
proven during the `2.3.0` Factorio `2.0` port.

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
- Replaced newer unavailable badge overlays on the `1.1` line with stock
  high-resolution target-era
  `__core__/graphics/icons/technology/constants/*` technology badge layers
  instead of bundling newer Factorio graphics.

## Factorio 1.1 Icon Substitutions

The `1.1` line does not package copied graphics from newer Factorio versions.
Technology tiles use stock high-resolution `1.1`
`__core__/graphics/icons/technology/constants/*` badge layers, matching
Factorio `1.1`'s own `util.technology_icon_constant_*` helpers. The smaller
`effect-constant/*` files remain utility sprites for effect rows and are not
used as technology tile overlays.

| Generated stream | Base technology art on `1.1` | Badge on `1.1` | Reason |
| --- | --- | --- | --- |
| Lab productivity | `research-speed-6`, then `research-speed-5`, then `military-science-pack` | `constant-mining-productivity.png` | Factorio `1.1` has native lab productivity but no high-resolution lab-productivity or recipe-productivity technology tile badge; the stock productivity helper uses mining-productivity art. |
| Rocket shooting speed | `rocketry` | `constant-speed.png` | Native `gun-speed` fire-rate modifier with stock speed badge. |
| Cannon shooting speed | `weapon-shooting-speed-3`, then `physical-projectile-damage-2`, then `cannon-shell` | `constant-speed.png` | Factorio `1.1` has no cannon-specific technology art, so MIR prefers stock projectile weapon technology art before falling back to the item. |
| Flamethrower shooting speed | `flamethrower` | `constant-speed.png` | Native `gun-speed` fire-rate modifier with stock speed badge. |
| Electric shooting speed | `discharge-defense-equipment` when Space Age electric weapon art is unavailable | `constant-speed.png` | Base `1.1` exposes electric discharge defense rather than Space Age Tesla technology art. |
| Character crafting speed | `automation-3`, then `automation-2`, then `repair-pack` | `constant-speed.png` | Factorio `1.1` has only a small effect-row crafting-speed sprite, not a high-resolution technology tile badge. |
| Character walking speed | `exoskeleton-equipment` | `constant-movement-speed.png` | Uses the stock equipment technology and stock movement-speed badge. |
| Character mining speed | `steel-axe` | `constant-mining.png` | Uses the stock mining technology and stock mining badge. |
| Character reach/build/drop distance | `steel-axe` | `constant-range.png` | Factorio `1.1` has no player-reach technology art, so MIR uses the target-era hand-tool technology with the stock range badge. |
| Character inventory/trash capacity | `toolbelt` | `constant-capacity.png` | Uses the stock inventory-capacity technology and stock capacity badge. |
| Worker robot battery | `logistic-robotics` | `constant-battery.png` | Uses stock robotics technology art with the stock battery badge. |

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

- Release candidate package:
  `dist/more-infinite-research_1.9.3.zip`, SHA-256
  `1723C10FEDD9A12003052991CC7574F1F6BF4E4ABC506F0323571DF680C0444B`,
  `298759` bytes, `121` entries, `0` forbidden release entries.
- Static validation passed for the `1.9.3` metadata and package shape.
- Factorio `1.1` binary validation passed with `D:\Programs\Factorio\1.1\bin\x64\factorio.exe`.
- The runtime gate loaded the packaged zip and ran the reduced `1.1` scenarios:
  direct effects, lab productivity owner skip, robot battery owner skip,
  merged inventory/trash capacity, settings surface, checkbox enable/disable,
  and weapon-speed overlap safety.
- The `factorio-1.1-direct-effects` runtime scenario now asserts every
  supported generated direct-effect technology has a stock high-resolution
  target-era technology constant badge and no unavailable newer badge path or
  smaller effect-row sprite as a tile overlay.
- The final visual-reviewed badge rebuild passed static validation and the
  Factorio `1.1` runtime fixture gate.
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
