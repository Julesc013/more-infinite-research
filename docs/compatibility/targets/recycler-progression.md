---
title: "Recycler Progression Compatibility"
status: current
applies_to: "4.0.0+"
audience: modpack-author
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-08-21
supersedes: []
superseded_by: []
---

# Recycler Progression Compatibility

Claim: MIR prevents the exact `recycler-progression_1.1.1` science-pack recycling routes from becoming first-acquisition prerequisites on Factorio `2.1`.

Recycler Progression moves generated hidden recycling-recipe unlocks onto `recycler-1`. That deliberately makes the first recycler useful early, but it does not mean `recycler-1` is how science packs are first acquired.

MIR classifies those hidden recipes as recycling or self-return routes according to their normalized inputs and outputs. They remain visible in route-decision explanations, but they cannot establish progression authority by default. Ordinary science-pack production remains selected, and MIR-generated technologies do not acquire a `recycler-1` prerequisite from those recipes.

The governed campaign `local-2-1-recycler-progression-routes` binds the exact `1.1.1` archive and a dedicated assertion fixture. Factorio `2.0` archive `1.0.0` is source-locked separately but remains unqualified until the f200 target-local campaign runs.

This evidence does not claim broad support for Recycler Progression entity tiers, balance, upgrades, or migrations.
