---
title: "More Infinite Research 1.8.0 Release Notes"
status: archived
applies_to: "0.18"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.8.0 Release Notes

`1.8.0` is the Factorio `0.18` bridge/archive compatibility package generated from the MIR 3 architecture. It starts from the `3.0.0` source anchor plus the portable lessons proven by the `2.3.0` Factorio `2.0` port and the `1.9.3` Factorio `1.1` reduced port.

It is not a feature-parity backport of the Factorio `1.1`, `2.0`, or `2.1` releases. It keeps only the older-line surfaces that can be generated safely: direct-effect infinite researches and supported base technology continuations.

## What Changed

- Retargeted package metadata to `version = "1.8.0"`, `factorio_version = "0.18"`, and `base >= 0.18`.
- Kept the reduced `1.9.3` posture: no recipe productivity, Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, agriculture, prototype cap settings, pipeline extent settings, or settings profiles.
- Extended validation metadata checks, fixture floors, settings visibility checks, and reduced-line runtime checks to recognize the Factorio `0.18` bridge target.
- Reused the global runtime-state adapter from the `1.1` port and kept unsupported runtime handlers disabled.
- Added explicit target-era localized names and descriptions to generated vanilla continuations so numbered continuation technologies do not show unresolved locale keys in older Factorio UIs.
- Added explicit modifier descriptions for reduced-line character, lab, inventory, and robot direct-effect tooltips because Factorio `1.0` does not provide every `modifier-description.*` key used by those effects.

## Icon Policy

The `0.18` bridge does not package graphics copied from newer Factorio versions. Factorio `0.18` and `1.0` do not ship the Factorio `1.1` `__core__/graphics/icons/technology/constants/*` technology badge assets. The local Factorio `1.0` prototype docs also do not document `icon` or `icons` fields on normal native technology modifiers. Those fields loaded, but the old UI ignored them for the native modifier rows that matter here.

Generated direct-effect technologies use target-era base technology art only. The Research productivity stream prefers stock `military-science-pack` technology art for its main tile, matching the `1.1` fallback when no Space Age research productivity technology is available. Character reach, walking speed, crafting speed, mining speed, inventory, robot battery, and weapon speed streams keep their target-era main technology textures and localized names/descriptions. The `0.18` bridge does not emit synthetic badge overlays or native modifier icon metadata for these effects.

## Supported Surface

- Target-supported direct-effect infinite researches: weapon shooting speed, cannon shooting speed, rocket shooting speed, electric shooting speed, flamethrower shooting speed, character crafting, character mining, character reach, character walking speed, character inventory/trash-slot capacity, lab productivity, and worker robot battery.
- Vanilla finite-chain continuations for supported base technologies such as braking force, lab research speed, laser shooting speed, weapon shooting speed, worker robot cargo size, and opt-in inserter capacity.
- Startup settings for supported streams and base continuations.

## Compatibility Checks

- Published package: `dist/more-infinite-research_1.8.0.zip`, SHA-256 `D785E6EBE7A72E6E9F01A3F89774A6AA30479430410447F603FEF1E0B9BD7B24`, `300620` bytes, `121` entries, `0` forbidden release entries.
- Static validation passed for the `1.8.0` metadata and package shape.
- Factorio `0.18` binary validation passed for the same published archive.
- The public dist archive and the runtime-validated validation archive contain the same `121` file entries with identical per-entry content hashes.
- Factorio `1.0` bridge-load validation passed with `D:\Programs\Factorio\1.0\bin\x64\factorio.exe`.
- The `1.0` bridge gate loaded the package, ran the reduced direct-effect scenario, lab productivity owner skip, robot battery owner skip, merged inventory/trash capacity, settings surface, checkbox enable/disable, and weapon-speed overlap safety scenarios.
- The reduced direct-effect fixture rejects unavailable newer badge paths, synthetic old-line badge overlays, and unsupported native modifier icon metadata.
- The reduced settings/profile fixture asserts generated vanilla continuations use explicit target-era localized names and descriptions, including the older `laser-turret-speed` chain.

## 1.8.0 Exclusion Manifest

This manifest is the handoff for the true Factorio `1.0` package. The `1.8.1` line must start from the validated `1.9.3` source plus proven `1.8.0` lessons, not by blindly changing the `1.8.0` metadata.

| Surface | 1.8.0 decision | Reason | 1.8.1 action |
| --- | --- | --- | --- |
| Recipe productivity | Cut | Factorio `1.1.110` rejected `change-recipe-productivity`; no `0.18` proof is available. | Re-probe on Factorio `1.0` only with a focused binary fixture before restoring. |
| Space Age, Quality, Recycler, Elevated Rails | Cut | Factorio `2.x` DLC surfaces. | Keep cut on `1.0`. |
| Cargo logistics modifiers | Cut | Factorio `2.1` direct-effect modifiers. | Keep cut on `1.0`. |
| Spoilage and agriculture streams | Cut | Factorio `2.x` runtime/prototype surfaces. | Keep cut on `1.0`. |
| Prototype cap and pipeline extent settings | Cut | Modern prototype limit/pipeline tuning surfaces are not part of the reduced old-line package. | Keep cut unless a `1.0` fixture proves a safe subset. |
| Settings profiles | Cut from runtime UI | Older target lines do not expose the MIRSET1 runtime profile surface used by modern packages. | Keep cut unless a `1.0` runtime fixture proves a portable profile path. |
| Technology constant badge overlays | Cut | Factorio `0.18` and `1.0` do not ship the Factorio `1.1` `__core__/graphics/icons/technology/constants/*` assets, and Factorio `1.0` does not provide a documented native modifier icon field for normal effects. | Keep cut for `1.8.1`; use main technology textures and locale unless a target binary proves a real icon surface. |
| Laser shooting speed continuation | Adapted | Factorio `1.0` uses `laser-turret-speed-*`; MIR keeps the modern setting key but extends the target-era source chain. | Carry this adapter into `1.8.1` if the `1.0` report diff confirms it avoids an accidental loss. |

## Known Boundaries

- Recipe productivity is not included on this line.
- Factorio `2.x` DLC surfaces are not included on this line.
- Newer Factorio core graphics are not bundled into the package.
- The published `1.8.0` archive is immutable bridge evidence. Do not rebuild it while preparing `1.8.1`; use a new patch release if the `0.18` payload must change.
