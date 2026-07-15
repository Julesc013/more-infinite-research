---
title: "More Infinite Research 0.7.0 Release Notes"
status: current
applies_to: "0.7.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-16
supersedes: []
superseded_by: []
---

# More Infinite Research 0.7.0

MIR 0.7.0 is a finite historical edition for Factorio 0.7.5. It restores selected research bonus continuations using target-era prototypes and configuration.

## Fixed

- Added the required `"factorio_version": "0.7"` compatibility field to `info.json`.
- Rebuilt the deterministic release archive so metadata validators no longer report `factorio_version` as missing.
- Kept the mod version as `"version": "0.7.0"` and the dependency floor as `base >= 0.7.5`.

## Included

- Five levels each of inserter capacity, gun-turret damage, bullet shooting speed, and bullet damage.
- Three toolbelt levels.
- Loaded `config.lua` controls for disabling a family or lowering its finite level count.
- Target-era science using `science-pack-1`, `science-pack-2`, `science-pack-3`, and `alien-science-pack`.

## Installation

Use this release with Factorio 0.7.5. Extract the ZIP into the target's mods directory; this Factorio line does not discover this package ZIP directly.

## Validation

- Exact Factorio 0.7.5 build 7026 fresh and second extracted-package prototype-cache regeneration: passed.
- Transactional target configuration was restored byte-for-byte.
- Static manifest, base evidence, locale, balance, deterministic-build, and 26 negative/invariant cases: passed.
- Release ZIP SHA-256: `AA328AFF81F3133BAC3F432ADC7AF52CC49EFF43E40D04EAD99DCFBA92542749`.
- Manual technology-tree, icon, locale-fit, and balance review remains pending.

## Known Limits

This is not a full current-MIR backport and does not claim native infinite research, formula counts, recipe or mining productivity, modern settings, dynamic discovery, Space Age support, or compatibility with newer Factorio lines.
