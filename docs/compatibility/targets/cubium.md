---
title: "Cubium Compatibility"
status: current
applies_to: "4.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-21
supersedes: []
superseded_by: []
---

# Cubium Compatibility

Claim: MIR provides exact, bounded interoperability for `cubium_1.0.30` on Factorio `2.1` in two tested areas only: loader-schema normalization and science-pack production-route selection.

Cubium `1.0.30` uses the obsolete singular `ambient-sound.planet` field. MIR changes those exact Cubium ambient-sound prototypes to the Factorio `2.1` `ambient-sound.planets` representation without changing the selected planet or sound content.

Cubium also adds cubic alternate recipes for eleven science packs at `cube-mastery-4`. MIR treats those recipes as ordinary alternate production routes. It retains each ordinary primary science recipe as the first-acquisition route, so MIR-generated research is not delayed behind `cube-mastery-4` merely because Cubium adds a later alternate.

The governed campaign `local-2-1-cubium-production-routes` binds the exact Cubium archive and runs a dedicated assertion fixture. It checks all eleven cubic routes, their `cube-mastery-4` unlock, deterministic multi-route selection, and the absence of `cube-mastery-4` from MIR-generated prerequisites.

This is not a broad Cubium support claim. Other Cubium progression, balance, runtime, and migration behavior remains outside this evidence boundary.
