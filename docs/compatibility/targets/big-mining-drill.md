---
title: "Big Mining Drill Compatibility"
status: current
applies_to: "3.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Big Mining Drill Compatibility

Claim: MIR covers visible Big Mining Drill-style crafting recipes through mining drill productivity.

Evidence:

- `mir-fixture-big-mining-drill`
- `mir-fixture-assert-big-mining-drill-productivity`

The reviewed explicit `research_mining_drill` stream owns this attachment. The generic automatic provider still returns `REVIEW_REQUIRED` when the combined mining-drill family exceeds its progression-span budget; that fail-closed diagnostic does not remove the separately reviewed stream effect.

Non-goal: native mining-yield productivity.
