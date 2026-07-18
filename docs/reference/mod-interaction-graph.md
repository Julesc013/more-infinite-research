---
title: "Semantic Mod Interaction Graph"
status: current
applies_to: "3.2.0+"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-18
supersedes: []
superseded_by: []
---

# Semantic Mod Interaction Graph

MIR represents each supported ecosystem as a support capsule with an exact mod closure, evidence, and semantic footprints. Footprints cover recipe or output families, technology effect owners, prerequisite components, science or lab families, surface or planet gates, prototype targets, and data-final-fixes removal or replacement behavior.

`scripts/New-MIRModInteractionGraph.ps1` computes every capsule pair deterministically. Pairs with no shared footprint route to an independent composition smoke. Pairs with shared footprints route to a targeted interaction campaign and must have one narrow A×B delta policy. The generator marks an uncovered overlap `BLOCKED_MISSING_DELTA_POLICY`.

The current graph covers ATAN Ash, Big Mining Drill, Space Age, and Space Age Galore. Six pairs yield four independent compositions and two overlapping pairs. Both overlaps have narrow delta policies; none is blocked.

A delta policy records only the shared footprints and pair-specific actions. `copies_full_capsule_policy` must be false. Individual support evidence is never treated as combination evidence, and a combination result does not expand either component's public compatibility claim.
