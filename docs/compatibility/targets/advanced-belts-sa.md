---
title: "Advanced Belts Compatibility"
status: current
applies_to: "3.2.3+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-30
supersedes: []
superseded_by: []
---

# Advanced Belts / AdvancedBeltsSA Compatibility

Claim: MIR covers structurally valid Advanced Belts-style belt, underground-belt, splitter, lane-splitter, loader, inserter, and module crafting recipes through their existing productivity streams. The match is based on the crafted item's final `place_result` entity type or module prototype, not the recipe or mod name.

MIR preserves these hard exclusions:

- recipes that explicitly set `allow_productivity = false`;
- recipes with an explicit zero productivity cap;
- recycling, hidden/internal, self-return, and other loop-risk recipes;
- returned fluids marked `ignored_by_productivity`.

Evidence:

- `mir-fixture-semantic-family-attach`
- `mir-fixture-assert-semantic-family-attach`
- `mir-fixture-assert-advanced-belts-sa-productivity`
- exact AdvancedBeltsSA 2.3.3 archive SHA-256 `A5D62D3EB189442574209625369E60EBFB04956921D7704A354823A80AAF241A`

The exact AdvancedBeltsSA 2.3.3 payload reached MIR's final data-stage assertion on Factorio 2.1.12 through a test-only metadata adapter. MIR emitted all twelve expected +0.5% belt-family effects and preserved all four productivity-ignored cryogenic fluid returns. Factorio then rejected AdvancedBeltsSA's own 2.0-style recipe category fields during final prototype validation. Therefore this is a fixture-qualified MIR behavior claim, not a claim that the unmodified AdvancedBeltsSA 2.3.3 archive loads on Factorio 2.1.

AdvancedBelts 2.0.7 targets Factorio 1.1, and AdvancedBeltsSA 2.3.3 targets Factorio 2.0. Their MIR target-line packages and exact 1.1/2.0 binary qualifications remain explicit backport obligations; MIR 3.2.3 itself targets Factorio 2.1.
