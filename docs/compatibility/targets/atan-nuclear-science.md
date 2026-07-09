---
title: "ATAN Nuclear Science Compatibility"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: []
---

# ATAN Nuclear Science Compatibility

Claim: MIR covers visible ATAN-style nuclear science pack recipes when the
science pack is an active lab input.

Evidence:

- `mir-fixture-atan-nuclear-science`
- `mir-fixture-assert-atan-nuclear-science-productivity`

Non-goal: atom forge crafting.

## Upstream Zip Status

Local supported-zip isolation for `3.0.0` found `atan-nuclear-science_0.3.3` failing on the tested Factorio `2.1` setup without MIR loaded because several recipes still use the pre-`2.1` `category` recipe field shape.

MIR `3.0.0` now applies an exact-version Factorio `2.1` loader-schema repair when `atan-nuclear-science_0.3.3` is loaded with MIR. The repair only normalizes known ATAN Nuclear Science recipe category fields into the `categories` table so Factorio can construct prototypes; it does not change ingredients, results, unlocks, science, productivity targets, or balance.

Repaired recipe IDs: `atomic-bomb`, `automation-science-pack`, `atan-atom-forge`, `breeder-fuel-cell`, `chemical-science-pack`, `centrifuge`, `explosive-plutonium-cannon-shell`, `explosive-uranium-cannon-shell`, `fission-reactor-equipment`, `fission-reactor-equipment-from-MOX-fuel`, `fission-reactor-equipment-from-plutonium`, `fusion-reactor-equipment`, `logistic-science-pack`, `military-science-pack`, `MOX-fuel-cell`, `nuclear-science-pack`, `nuclear-science-pack-from-plutonium`, `plutonium-atomic-artillery-shell`, `plutonium-cannon-shell`, `plutonium-fuel-cell`, `plutonium-rounds-magazine`, `production-science-pack`, `uranium-cannon-shell`, `uranium-fuel-cell`, `uranium-rounds-magazine`, and `utility-science-pack`.

MIR's public productivity claim remains the fixture-backed science-pack recipe productivity path only.
