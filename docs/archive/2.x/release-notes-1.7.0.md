---
title: "More Infinite Research 1.7.0 Release Notes"
status: archived
applies_to: "0.17"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-10
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 1.7.0 Release Notes

MIR `1.7.0` is a reduced native-infinite edition for Factorio `0.17`.

It is derived from the MIR 3 compatibility compiler architecture, the validated
`1.8.x` old-line ports, and current `dev` portable fixes. It keeps only the
Factorio `0.17`-supported direct-effect infinite researches and base technology
continuations that pass target binary validation.

It is not a full MIR `3.0.0` backport and is not a metadata retarget of the
Factorio `1.0` package.

## What Changed

- Retargeted package metadata to `version = "1.7.0"`,
  `factorio_version = "0.17"`, and `base >= 0.17`.
- Kept the modern non-Space-Age science-pack family used by Factorio `0.17`.
- Kept the older-line `global` runtime state adapter.
- Kept target-supported direct-effect infinite researches and base technology
  continuations.
- Anchored dedicated rocket, cannon, flamethrower, and electric shooting speed
  research to target-era unlock prerequisites.
- Removed duplicate rocket and cannon-shell speed ownership from MIR's generated
  weapon shooting speed continuation by default when dedicated replacement
  research is active.
- Excluded disabled tutorial and scenario technologies from inferred
  science-pack unlock prerequisites.
- Treated already-enabled science-pack recipes as requiring no unlock
  prerequisite, preventing Factorio `0.17`'s disabled `basic-mining` tutorial
  technology from blocking generated research.
- Removed Factorio `2.x` and DLC surfaces from the package.
- Left recipe productivity, Space Age, Quality, Recycler, Elevated Rails, cargo
  logistics, spoilage, agriculture, prototype cap settings, pipeline extent
  settings, settings profiles, and newer badge overlays out of the `0.17` line.
- Retargeted branch-local support fixture metadata to Factorio `0.17`.

## Supported Surface

- Direct-effect infinite researches that load in the Factorio `0.17` binary.
- Base technology continuations that load with Factorio `0.17` technology and
  science-pack schemas.
- Target-era technology art without newer badge overlays or unsupported native
  modifier icon metadata.

## Exclusions

- No recipe productivity support is claimed for this line.
- No Space Age, Quality, Recycler, Elevated Rails, cargo logistics, spoilage, or
  agriculture support is claimed for this line.
- No Factorio `2.x` runtime `storage` table support is required; Factorio
  `0.17` uses the old `global` table.
- No newer Factorio core graphics are bundled or used as generated technology
  badge overlays.
- No feature parity with Factorio `1.0`, `1.1`, `2.0`, or `2.1` is claimed.

## Compatibility Checks

- Release-candidate package:
  `dist/more-infinite-research_1.7.0.zip`, SHA-256
  `3FA9419253C3E79572305E983B0443CC657683CC761DA3F4292FBF798B8C613C`,
  `301428` bytes, `121` entries, `0` forbidden release entries.
- Static validation passed for the `1.7.0` metadata and package shape.
- Factorio `0.17` binary validation passed with
  `D:\Programs\Factorio\0.17\bin\x64\factorio.exe`.
- The public dist archive and the runtime-validated validation archive contain
  matching package content.
- The Factorio `0.17` gate loaded the package, ran the reduced direct-effect
  scenario, lab productivity owner skip, robot battery owner skip, merged
  inventory/trash capacity, reduced settings surface, checkbox
  enable/disable, and weapon-speed overlap safety scenarios.
- The weapon-speed overlap safety scenario also verifies dedicated weapon speed
  streams depend on their target-era unlock technologies.
- The generated-prerequisite safety fixture rejects any generated stream that
  depends on a technology with `enabled = false` or remains blocked after the
  normal unlock-all command.
- An exact-dist Factorio `0.17.79` unlock-all probe advanced all eleven
  generated direct-effect technologies to level `2` with zero unmet or
  disabled prerequisites.

## Release Wording

Use:

```text
MIR 1.7.0 is a reduced native-infinite edition for Factorio 0.17.

It is derived from the MIR 3 compatibility compiler architecture and the
validated 1.8.x old-line ports, but includes only Factorio 0.17-supported
direct-effect infinite researches and base technology continuations.
```

Do not describe `1.7.0` as a full MIR `3.0.0` backport, as the same feature set
as `1.0`, as recipe productivity support, or as Space Age support.
