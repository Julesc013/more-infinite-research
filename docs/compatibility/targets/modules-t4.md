---
title: "Tier 4 Modules Compatibility"
status: current
applies_to: "3.0.5+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-11
supersedes: []
superseded_by: []
---

# Tier 4 Modules Compatibility

Claim: MIR covers recipes that output Tier 4 Modules module prototypes through the existing Module productivity research. Matching uses the final module prototype tier, not `-4` names or a mod-specific override.

Evidence:

- `fixtures/assert-prototype-limits` tier-4 module fixture
- Tier 4 Modules `2.2.2` source-archive load check on Factorio `2.1.9`
- combined exact-dist load check with Finite Productivity Technologies `0.1.1` and the complete official Space Age bundle

Tier 4 and later module recipes receive +1% productivity per MIR research level. MIR does not rewrite module effects, module categories, technologies, recipes, or settings owned by Tier 4 Modules.

Non-goal: dynamic infinite research that changes placed module effects.
