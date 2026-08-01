---
title: "Advanced Belts Space Age Compatibility"
status: current
applies_to: "2.5.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-01
supersedes: []
superseded_by: []
---

# Advanced Belts Space Age Compatibility

Candidate claim: MIR covers structurally valid Advanced Belts-style belt, underground-belt, splitter, lane-splitter, loader, inserter, and module crafting recipes through their existing productivity streams. Matching uses the crafted item's final `place_result` entity type or module prototype, not the recipe or mod name.

MIR preserves these hard exclusions:

- recipes that explicitly set `allow_productivity = false`;
- recipes with an explicit zero productivity cap;
- recycling, hidden/internal, self-return, and other loop-risk recipes;
- returned fluids marked `ignored_by_productivity`.

Planned evidence:

- `mir-fixture-semantic-family-attach`;
- `mir-fixture-assert-semantic-family-attach`;
- `mir-fixture-assert-advanced-belts-sa-productivity`;
- exact AdvancedBeltsSA 2.3.3 archive SHA-256 `A5D62D3EB189442574209625369E60EBFB04956921D7704A354823A80AAF241A`.

The 2.5.0 target uses the unmodified AdvancedBeltsSA 2.3.3 archive on its native Factorio 2.0 line. Exact Factorio 2.0.77 qualification is pending for P11; until that run passes, this page records implementation scope rather than a public load-checked claim.

AdvancedBelts 2.0.7 targets Factorio 1.1 and remains a separate target-line projection and exact-binary qualification obligation.
