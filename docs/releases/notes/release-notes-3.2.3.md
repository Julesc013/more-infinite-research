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

## Advanced Belts

- The Factorio 2.1 structural fixture covers arbitrary belt, loader, inserter, and module prototype families without relying on mod-specific names.
- A data-stage probe against the exact `AdvancedBeltsSA_2.3.3.zip` payload observed all twelve expected Extreme, Ultimate, and High-speed belt, splitter, lane-splitter, and underground-belt effects.
- High-speed cryogenic recipes keep their returned coolant excluded from productivity.
- AdvancedBeltsSA 2.3.3 declares Factorio 2.0 and uses the Factorio 2.0 recipe-category schema, so it is not claimed as a complete Factorio 2.1 archive load.
- The structural matcher is designed to be portable to the Factorio 2.0 and 1.1 target lines, but those lines require separate projected packages and exact target-binary qualification; MIR 3.2.3 itself remains a Factorio 2.1 release.

## Release status

The package identity and qualification evidence will be inserted after the candidate is frozen. Publication, promotion, and tagging remain blocked until exact local, manual, and protected release gates pass.

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
