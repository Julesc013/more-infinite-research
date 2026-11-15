---
title: "MIR 5.0.15 beta release notes"
status: draft
applies_to: "MIR 5.0.15 GitHub prerelease candidate"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-515-release-notes
---

Repairs productivity compatibility and worker cargo upgrades with authenticated research history.

- Accept complete productivity preservation effects when native public research covers extra recipes.
- Return explicitly prepared default worker research to its ordinary owner while retaining earned levels and unfinished or queued work.
- Admit supported engine patches for qualified older default worker upgrades.
- Show more useful effect/reference details in remaining productivity refusals; improve the external log collector.

Keep a protected original save and its matching mods/settings, and upgrade a copy first. Saves without authenticated earlier ownership still need their original history; this update does not reconstruct erased research or qualify every provider and finite-research transition.

This is a GitHub beta. Library input/export/client-lifecycle checks and broader performance acceptance remain unfinished for stable.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.15/docs/support.md).
