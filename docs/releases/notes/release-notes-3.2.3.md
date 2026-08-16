---
title: "MIR 3.2.3 Release Notes"
status: current
applies_to: "3.2.3"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-31
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
- The C29 predecessor fixture saved and independently reloaded the upgraded Space Age game. The final exact C30 transition rerun remains a release-qualification gate.

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

Candidate C30 is frozen. Its deterministic package reproduced twice and its exact automatic-action, structural-logistics, compiler-contract, Base, and Space Age focused scenarios passed. C29 predecessor results remain diagnostic only; complete exact C30 qualification, upgrade, approved delta, ecosystem, paired performance, manual acceptance, protected qualification, sealing, promotion, publication, and tagging remain pending.

<!-- MIR-CONTROL-PLANE-IDENTITY:BEGIN -->
## Immutable release identity

> Generated from `.mir/releases/3.2.3.json`. The typed record is authoritative.

| Field | Value |
| --- | --- |
| State | `publicly-verified` |
| Candidate | `C30` |
| Package source commit | `c1fd8b932c8d916a14925678056e08893b87b2db` |
| Archive SHA-256 | `0DD4048F1DA65B506DBCCD67D2B0D08A89DFBE54169C1497563093B8F55F51F2` |
| Content SHA-256 | `2935EE1C77619DF90821658A6C42A1F428D87BE858BB10746E792760A40928B9` |
| Tag | `3.2.3` |
| Tag commit | `1abe07573cde814c3cacf6153b5ae64dee4038ba` |
| Assurance exceptions | `C30-TIMEBOXED-PUBLICATION-2026-08-01` |

<!-- MIR-CONTROL-PLANE-IDENTITY:END -->
