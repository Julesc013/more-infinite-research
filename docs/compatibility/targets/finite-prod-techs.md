---
title: "Finite Productivity Technologies Compatibility"
status: current
applies_to: "3.0.5+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-11
supersedes: []
superseded_by: []
---

# Finite Productivity Technologies Compatibility

Claim: MIR cooperates with Finite Productivity Technologies `0.1.1+` as a load-after post-processor.

Evidence: Finite Productivity Technologies `0.1.1` source-archive load check on Factorio `2.1.9`, plus a combined exact-dist check with Tier 4 Modules `2.2.2` and the complete official Space Age bundle.

The external mod declares a hidden optional dependency on MIR, so its `data-final-fixes` pass sees MIR's emitted recipe-productivity technologies and the selected final recipe caps. MIR intentionally does not add the reverse dependency, which would create a dependency cycle.

Non-goal: MIR does not copy or own the external mod's finite-level formula.
