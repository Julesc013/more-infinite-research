---
title: "ATAN Ash Compatibility"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: []
---

# ATAN Ash Compatibility

Claim: MIR adds productivity to ash separation only.

Evidence:

- `mir-fixture-atan-ash`
- `mir-fixture-assert-atan-ash-separation`
- Stream `mir-prod-atan-ash-separation`

Non-goals: landfill, brick, nutrient, foundation, tile, and recovery-style ash
sink recipes.

## Upstream Zip Status

Local supported-zip isolation for `3.0.0` found `atan-ash_2.2.1` failing on the tested Factorio `2.1` setup without MIR loaded because several recipes still use the pre-`2.1` `category` recipe field shape.

MIR `3.0.0` now applies an exact-version Factorio `2.1` loader-schema repair when `atan-ash_2.2.1` is loaded with MIR. The repair only normalizes known ATAN Ash recipe category fields into the `categories` table and known result `probability` fields into `independent_probability` so Factorio can construct prototypes; it does not change ingredients, result amounts, unlocks, science, productivity targets, or balance.

Repaired recipe IDs: `atan-ash-seperation`, `atan-foundation-from-ash`, `atan-landfill-from-ash`, `atan-nutrients-from-ash`, and `atan-stone-brick-from-ash`.

MIR's public productivity claim remains the fixture-backed ash separation productivity family only.
