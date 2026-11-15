---
title: "MIR 5.0.15 beta release notes"
status: current
applies_to: "MIR 5.0.15 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-515-release-notes
---

Improves safe upgrades for certain prepared worker-cargo saves and makes overlapping productivity effects easier to diagnose.

- Preserve earned levels and unfinished default worker-cargo research from prepared MIR 5.0.11 saves.
- Preserve authenticated older default worker-cargo upgrades when moving from Factorio 2.1.23 to 2.1.24.
- Accept a complete productivity-preservation effect when its public research also covers other recipes.
- Name the rejected productivity component and its public reference in startup errors.

Update a copy first. Keep a protected original save with its matching mods and startup settings. Histories missing the required ownership evidence may still need that original configuration; MIR cannot reconstruct erased research.

This is a GitHub prerelease, not stable. Graphical Library and multiplayer checks, plus broader performance testing, remain unfinished.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.15/docs/support.md).
