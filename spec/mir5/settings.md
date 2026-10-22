---
title: "Settings and research semantics"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-settings-specification
---

# Settings and research semantics

`SET-01` — Preserve exact historical IDs, types, defaults, allowed values, target availability, hidden states, units and sentinel meanings. A retained name with a new silent meaning is not compatibility. Internal naming cleanup must not rename saved setting IDs.

Read the actual published package, resolved prototype output and independently intended behavior. Existing `ips-*` stream settings and `mir-*` native/global settings remain obligations where delivered. The seed continuity inventory identifies subjects; it is not the completed setting catalogue.

## Resolution order

Recover and reproduce actual default → profile-import → user/effective-setting precedence. Do not assume raw `settings.startup` alone reproduces the previous profile-import behavior. Parse an import string once using a restricted data codec; never `load`/execute it. Unknown, malformed and out-of-range values retain documented behavior or receive an explicit reviewed correction.

Resolve effective values once per active definition/feature. No complete setting-registry copy in every technology constructor. Settings-stage code may share small identity declarations with data/runtime code but must not import prototype-world analysis. Extensions declare their settings in their own settings-stage files.

## Required continuity subjects

- Stream enable, base cost, linear increment, growth, maximum, research time and per-level effect.
- Native-chain enable/cost/effect/cap overrides, including native inherit/unset behavior.
- Global research scaling and worker-robot-speed maximum.
- All existing science ingredient policies, including broad `all`/mod-progression behavior; lab `reduce`, `skip`, `engine-default` semantics.
- Native competing-owner preference and weapon-speed adjustment policy.
- Recipe/machine/module effect limits, self-recycling scope and return behavior, module permissions, positive-power safeguard, pipeline extent.
- Profile import/export, diagnostics, icon/visibility choices, scripted features and Library behavior.
- Former implementation selectors: compatible alias/deprecation only after their old outcomes are explicitly accounted for.

`SET-02` — Preserve numeric versus formula costs, initial-level offsets, rounding, time, stage boundaries and global/per-family scalar interactions. Do not replace all families with one illustrative formula. Compare native evaluated costs at boundary/high levels as well as formula text where relevant. Reject nonfinite values; do not conflate a literal zero with inherit or unlimited.

## Disablement and caps

A user-disabled new research, a hidden identity retained for saves, and a technology disabled by another mod are not interchangeable. The exact existing behavior needs its own expected result. Do not omit an established prototype merely to save load time.

`SET-03` — Lowering a configured cap below earned research must preserve earned effects/investment. Uncapping may restore only enablement owned by MIR. Test defaults, zero/unlimited, cap 10, level 10/11 boundary, already-earned-above-cap, partial current research and queued entries. A native `max_level` replacement is accepted only where the same semantics are proven.

## Validation selection

Default output comparison plus each setting's meaningful boundary values and targeted interaction pairs is required. Exhaustive combinations are not implied. A setting is verified by its changed native/runtime effect, not by its presence in the settings screen. Changing a settings contract requires its scenario to rerun; a documentation typo does not.

Retain exact locale keys and explanatory warnings where their behavior still applies. Keep shipped translations rather than replacing them with generated English-only prose.

## Separate settings definitions, values and lifetime

`SET-04` — Settings prototypes are declared in the settings stage; Factorio loads configured values after that stage. The data stage reads startup values; it does not add settings. Runtime-global and runtime-per-user settings, where actually delivered, have their own allowed consumers and change events. User-specific presentation settings must not alter force-wide effects silently.

Keep the lightweight identity/default catalogue available to the settings stage without importing the Generator or prototype registry analysis. The same historical key is not independently redefined by settings, API and Library. The data/runtime configuration reader reproduces the same accepted precedence without persisting a second authority.
