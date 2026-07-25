---
title: "More Infinite Research 0.12.0 Release Notes"
status: current
applies_to: "0.12.0"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-16
supersedes: []
superseded_by: []
---

# More Infinite Research 0.12.0

MIR 0.12.0 is a finite historical edition for Factorio 0.12.35. It restores selected research bonus continuations using target-era prototypes and configuration.

## Fixed

- Added the required `"factorio_version": "0.12"` compatibility field to `info.json`.
- Rebuilt the deterministic release archive so metadata validators no longer report `factorio_version` as missing.
- Kept the mod version as `"version": "0.12.0"` and the dependency floor as `base >= 0.12.35`.

## Included

- Five levels each of inserter capacity, gun-turret damage, bullet shooting speed, and bullet damage.
- Three levels each of toolbelt and logistic trash slots.
- Loaded `config.lua` controls for disabling a family or lowering its finite level count.
- Target-era science using `science-pack-1`, `science-pack-2`, `science-pack-3`, and `alien-science-pack`.

## Installation

Use this release with Factorio 0.12.35. The archive is ZIP-native and can be placed directly in the target's mods directory.

## Validation

- Exact Factorio 0.12.35 build 18124 fresh-create and bounded server reload: passed.
- Static manifest, base evidence, locale, balance, deterministic-build, and 26 negative/invariant cases: passed.
- Release ZIP SHA-256: `5171CD073A632AA30769FD9567F44AD2331BB5E7B852EC9F8576798398816612`.
- Manual technology-tree, icon, locale-fit, and balance review remains pending.

## Known Limits

This is not a full current-MIR backport and does not claim native infinite research, formula counts, recipe or mining productivity, modern settings, dynamic discovery, Space Age support, or compatibility with newer Factorio lines.
