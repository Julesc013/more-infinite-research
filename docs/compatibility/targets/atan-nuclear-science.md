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

Local supported-zip isolation for `3.0.0` found
`atan-nuclear-science_0.3.3` failing on the tested Factorio `2.1` setup
without MIR loaded. That failure is treated as an upstream zip/schema blocker,
not as MIR behavior.

MIR's public claim remains the fixture-backed science-pack recipe productivity
path only.
