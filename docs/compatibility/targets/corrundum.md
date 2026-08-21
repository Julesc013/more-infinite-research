---
title: "Corrundum Compatibility"
status: current
applies_to: "4.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-21
supersedes: []
superseded_by: []
---

# Corrundum Compatibility

Claim: MIR provides an exact-version Factorio `2.1` loader-schema repair for `corrundum_1.0.47` only.

Corrundum `1.0.47` declares the obsolete singular `ambient-sound.planet` field. On the tested Factorio `2.1.14` engine, prototype validation rejects that field and requires the `ambient-sound.planets` table instead.

When this exact Corrundum version is active on Factorio `2.1`, MIR moves the Corrundum planet selector into a one-entry `planets` table and removes the obsolete field. The repair does not change sounds, recipes, ingredients, results, technologies, unlocks, science requirements, progression, or balance.

The governed local campaign `local-2-1-corrundum-maxcap-13` roots the exact locally locked `PlanetsLib_1.19.5` and `corrundum_1.0.47` archives. It passed its loader-repair assertion and all ten maximum-level log assertions on Factorio `2.1.14`: nine capped technologies reported an effective absolute cap of `13`, and no maximum-level conflict was emitted.

That is exact automated runtime evidence, not broad Corrundum support. Manual visual UI review is still unproven, and science-prerequisite behavior remains diagnostic-only until its separate exact runtime assertions pass.
