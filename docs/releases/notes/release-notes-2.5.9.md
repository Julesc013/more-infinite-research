<!-- MIR3-TERMINAL-SHADOW release=2.5.9 target=2.0 baseline=2.5.5 pre-dot5=2.5.0 candidate=unassigned source-frozen=false -->

---
title: "MIR 2.5.9 Planning Notes"
status: draft
applies_to: "2.5.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-12
supersedes: []
superseded_by: []
---

# MIR 2.5.9 Planning Notes

MIR 2.5.9 is the terminal Factorio 2.0 projection from the immutable 2.5.5 baseline. Its only admitted product correction is `SciencePackProductionRoutePolicyV1`: alternate recipes for the same science pack are treated as independent routes, and the deterministic earliest safe route is selected before technology or recipe names can break a tie.

The generic Factorio 2.0 fixture proves that adding a lexically earlier but downstream route cannot delay an already-reachable science pack. Direct unmodified Cubium 1.0.28 evidence remains pending authenticated acquisition, so these notes do not claim direct Cubium support beyond the generic invariant.

The target retains stable generated technology IDs, settings, and migration behavior. A direct five-archetype 2.5.5-to-2.5.9 upgrade matrix covers base/default generation, Space Age native ownership, automatic family creation, base continuations, and source-only compatibility-mod removal.

This is an unfrozen shadow. No candidate ID, final package identity, tag, release, or publication authority is assigned until the all-nine fixed point is accepted and terminal source freeze occurs.
