---
title: "MIR 3.2.3 Release Notes"
status: current
applies_to: "3.2.3"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-30
supersedes: []
superseded_by: []
---

# MIR 3.2.3

MIR 3.2.3 is a focused Space Age progression and modded-logistics productivity hotfix.

## Fixed

- Ice productivity now requires cryogenic science, so its Aquilo recipe coverage is no longer available from Nauvis progression alone.
- Ice-platform and space-platform-foundation crafting have moved out of Landfill productivity into a separate, default-on Platform productivity technology.
- Platform productivity grants +10% ice-platform and +5% space-platform-foundation productivity per level.
- Platform productivity uses Landfill's science progression with cryogenic science replacing metallurgic science.
- Modded belt, underground-belt, splitter, lane-splitter, loader, and inserter recipes can join their established productivity streams through final `place_result` prototype structure instead of name conventions.
- Recipes that explicitly deny productivity or set a zero productivity cap remain excluded from structural attachment.

## Upgrading from 3.2.2

- Existing Landfill Productivity and Ice Productivity levels are retained.
- Current Ice Productivity research and fractional progress are retained; completing later levels now requires cryogenic science.
- Platform Productivity starts unresearched. Landfill levels are not copied into it, because that would bypass the new Aquilo gate and convert the earlier +2%/+1% bonuses into +10%/+5% bonuses.
- After configuration change, Landfill no longer owns either Platform recipe and each recipe has exactly one owner: Platform Productivity.
- The exact 3.2.2-to-C29 upgrade fixture saved and independently reloaded the upgraded Space Age game.

## Compiler efficiency

- Structural logistics discovery now builds one immutable entity/item/module fact index per compilation instead of repeatedly scanning prototype types.
- Unlock-derived science and emitted effects consume the same cached stream-match result, so a stream's membership is computed at most once for one exact descriptor, recipe-fact, and target-profile identity.
- Runtime fixtures enforce one index build, one recipe-fact scan, deterministic randomized-order output, and zero duplicate effect owners.

## Advanced Belts

- The Factorio 2.1 structural fixture covers arbitrary belt, loader, inserter, and module prototype families without relying on mod-specific names.
- A data-stage probe against the exact `AdvancedBeltsSA_2.3.3.zip` payload observed all twelve expected Extreme, Ultimate, and High-speed belt, splitter, lane-splitter, and underground-belt effects.
- High-speed cryogenic recipes keep their returned coolant excluded from productivity.
- AdvancedBeltsSA 2.3.3 declares Factorio 2.0 and uses the Factorio 2.0 recipe-category schema, so it is not claimed as a complete Factorio 2.1 archive load.
- The structural matcher is designed to be portable to the Factorio 2.0 and 1.1 target lines, but those lines require separate projected packages and exact target-binary qualification; MIR 3.2.3 itself remains a Factorio 2.1 release.

## Release status

Candidate C29 is frozen and its deterministic package, full static gate, focused exact runtime scenarios, and exact 3.2.2 upgrade/reload transition have passed. Candidate aggregation, paired performance, manual acceptance, protected qualification, sealing, promotion, publication, and tagging remain pending.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `.mir/releases/3.2.3.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `package-built` |
| Candidate | `C29` |
| Package source commit | `c5d11aab76ffee479ca4aaba3bb8fa4387918762` |
| Archive SHA-256 | `BC5898FC3BE09BAC0F55C751D21E05BF1F82132C98B2FA92A39BC9809D7647A1` |
| Content SHA-256 | `4AA68E4E381D691F97B4A8721AFF8BFEA9E992E9A8423D972990F0DCA66309B4` |
| Tag | `pending` |
| Tag commit | `pending` |
| Assurance exceptions | `pending` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
