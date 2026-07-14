---
title: "More Infinite Research 1.8.1 Release Notes"
status: archived
applies_to: "1.0"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.8.1 Release Notes

MIR `1.8.1` is the maintained Factorio `1.0` compatibility port of the MIR 3 architecture. It is derived from the validated Factorio `1.1` port and the Factorio `0.18` bridge lessons, with Factorio `1.0`-specific metadata, validation, and restored target-supported behavior where proven.

It is not a metadata bump of `1.8.0`. The `1.8.0` archive remains the frozen Factorio `0.18` bridge package. The `1.8.1+` line is the direct Factorio `1.0` support line.

## What Changed

- Retargeted package metadata to `version = "1.8.1"`, `factorio_version = "1.0"`, and `base >= 1.0`.
- Started from the reduced `1.9.3` source posture plus proven `1.8.0` bridge lessons and current portable dev fixes.
- Kept supported direct-effect infinite researches and base technology continuations.
- Kept recipe productivity, Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, agriculture, prototype cap settings, pipeline extent settings, settings profiles, and newer technology badge overlays out of the Factorio `1.0` package.
- Carried the `global` runtime state adapter for older target lines.
- Carried target-era localized names and descriptions for generated vanilla continuations, including the older `laser-turret-speed` chain.
- Removed newer science-pack names from the Factorio `1.0` direct-effect and base-extension defaults.

## Supported Surface

- Target-supported direct-effect infinite researches: weapon shooting speed, cannon shooting speed, rocket shooting speed, electric shooting speed, flamethrower shooting speed, character crafting, character mining, character reach, character walking speed, character inventory/trash-slot capacity, lab productivity, and worker robot battery.
- Vanilla finite-chain continuations for supported base technologies such as braking force, lab research speed, laser shooting speed, weapon shooting speed, worker robot cargo size, and opt-in inserter capacity.
- Startup settings for supported streams and base continuations.

## Exclusions

- No recipe productivity support is claimed for this line.
- No Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, or agriculture support is claimed for this line.
- No Factorio `2.x` runtime `storage` table support is required; Factorio `1.0` uses the old `global` table.
- No newer Factorio core graphics are bundled or used as generated technology badge overlays.
- No feature parity with Factorio `1.1`, `2.0`, or `2.1` is claimed.

## Compatibility Checks

- Published package candidate: `dist/more-infinite-research_1.8.1.zip`, SHA-256 `B1622AB0BC6D72265842D698781DBE21B7286662E29FB6992057FBCFF87D8E29`, `300526` bytes, `116` entries, `0` forbidden release entries.
- Static validation passed for the `1.8.1` metadata and package shape.
- Factorio `1.0` binary validation passed with `D:\Programs\Factorio\1.0\bin\x64\factorio.exe`.
- The public dist archive and the runtime-validated validation archive contain the same `116` file entries with identical per-entry content hashes.
- The Factorio `1.0` gate loaded the package, ran the reduced direct-effect scenario, lab productivity owner skip, robot battery owner skip, merged inventory/trash capacity, reduced settings surface, checkbox enable/disable, and weapon-speed overlap safety scenarios.
- The reduced direct-effect check rejects unavailable newer badge paths, synthetic old-line badge overlays, unsupported native modifier icon metadata, and newer direct-effect science-pack names.

## Release Wording

Use:

```text
MIR 1.8.1 is the maintained Factorio 1.0 compatibility port of the MIR 3 architecture.

It is derived from the validated Factorio 1.1 port and the Factorio 0.18 bridge lessons, with Factorio 1.0-specific metadata, validation, and restored target-supported behavior where proven.
```

Do not describe `1.8.1` as a full MIR `3.0.0` backport, as the same feature set as `1.1`, as the same feature set as `0.18`, as recipe productivity support, or as Space Age support.
