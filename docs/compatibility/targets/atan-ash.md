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

Local supported-zip isolation for `3.0.0` found `atan-ash_2.2.1` failing on
the tested Factorio `2.1` setup without MIR loaded. That failure is treated as
an upstream zip/schema blocker, not as MIR behavior.

MIR's public claim remains the fixture-backed ash separation productivity
family only.
