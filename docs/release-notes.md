---
title: "MIR 5.0.14 beta release notes"
status: current
applies_to: "MIR 5.0.14 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-13
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-514-release-notes
---

Fixes worker cargo save upgrades that reject unrelated mod changes despite having saved MIR ownership history.

- Preserve earned worker cargo levels and unfinished or queued research during these recorded-default upgrades.
- Include the previous MIR version and saved-route information in changed-selection refusals.

Keep a protected original save and its matching mods/settings. Saves missing earlier ownership data still need that original configuration; this update does not reconstruct erased research. Update a copy before adopting it.

This is a GitHub beta. Library input/export/client-lifecycle checks and broader performance acceptance remain unfinished for stable.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.14/docs/support.md).
