---
title: "More Infinite Research 2.3.0 Release Notes"
status: archived
applies_to: "2.0"
audience: maintainer
doc_type: archive
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: ["../../releases/README.md"]
---
# More Infinite Research 2.3.0 Release Notes

`2.3.0` is the Factorio `2.0` backport of the MIR 3 compatibility compiler work prepared for `3.0.0`.

## What Changed

- Retargeted package metadata to `factorio_version = "2.0"` and `base >= 2.0`.
- Kept Quality hidden and optional, and kept Space Age optional without Factorio `2.1` dependency floors.
- Removed the Factorio `2.1` cargo bay unloading distance and cargo landing pad count research streams from the Factorio `2.0` package.
- Kept generated technology IDs stable for every stream that remains available on the Factorio `2.0` line.
- Kept exact ATAN loader-schema repairs for the known supported upstream ATAN Ash and ATAN Nuclear Science packages.
- Restored Factorio `2.0` science-pack fixture shape so custom and ATAN-style science packs are represented as `tool` prototypes during the backport checks.
- Added reviewed expected-failure rules for the Factorio `2.0` local zip sweep so incomplete dependency closures and no-MIR-reproduced upstream load failures stay visible without blocking MIR release gates.

## Compatibility Checks

- Static checks passed for the `2.3.0` metadata and package shape.
- Factorio `2.0.77` runtime checks passed across the existing base, Space Age, science-pack, lab-policy, productivity-family, pipeline, ATAN, AAI loader, Big Mining Drill, Omega Drill, weapon-speed, and base-extension scenarios.
- Targeted local zip checks passed for AAI Containers, AAI Industry, AAI Loaders, Big Mining Drill, Equipment Gantry, Fluid Must Flow, Jetpack, and Robot Attrition from `C:\Projects\Factorio\testmods_2.0`.
- The Factorio `2.0` BZ representative local scenario passed with zero grouped failures.
- The ATAN Factorio `2.0` isolation matrix passed for ATAN Ash, ATAN Nuclear Science with Space Age, ATAN Air Scrubbing, and the combined ATAN stack with MIR.
- The full `testmods_2.0` local root sweep covered 314 local roots and reconverted to zero unexpected grouped failures after reviewed external failures were classified.

## Known Boundaries

- Factorio `2.1` cargo logistics technologies are not included in this Factorio `2.0` backport.
- MIR still does not claim broad support for every local zip in the exploratory library; missing dependency closures, local archives that fail without MIR, and external ownership suppressions remain evidence for triage rather than broad compatibility claims.
- `nauv-so` local sweep rows where no active lab accepts MIR's configured base science packs are expected safe skips, not generated research.
