---
title: "Mining Drill Manufacturing Capability"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Mining Drill Manufacturing Capability

Mining drill manufacturing identifies recipes that craft mining drills. It is separate from native mining-yield productivity.

Evidence:

- item exists;
- item has `place_result`;
- placed entity type is `mining-drill`;
- a visible recipe produces the item;
- existing MIR mining-drill productivity or a future validated stream owns the effect.

Known fixtures: [Big Mining Drill](../compatibility/targets/big-mining-drill.md) and `omega-drill`.

