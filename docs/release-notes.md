---
title: "MIR 5.0.12 beta release notes"
status: current
applies_to: "MIR 5.0.12 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-11
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-512-release-notes
---

Repairs worker cargo upgrade handling and compatibility with expanded productivity research on Factorio 2.0 and 2.1.

- Preserve admitted earlier MIR 5 worker cargo levels and unfinished research in permanent native research, supporting later provider changes without guessing erased history.
- Retain Secretas worker history across successive updates, and keep Ferrum robotics science in continued cargo research.
- Preserve complete productivity credits when other mods expand recipe research effects.
- Allow Bob's Warfare with mods that set recipe productivity caps, preserving their configured limits.
- Restore missing translated startup-setting labels and improve Library filter layout, wrapping, search text and German wording.

Protect the original save and its matching mods/settings. First update a copy with the previous mod selection and settings, save separately, then make a supported provider change. After a successful native ownership transfer, the legacy worker preparation command is unnecessary. An already-clamped or unknown history can still require the protected original; keep it if the upgrade refuses.

This is a GitHub beta. Full Library interaction/export/client and performance qualification remain unfinished. Not every reported save or mod combination has been reproduced.

[Installation, upgrade procedures and support limits](https://github.com/Julesc013/more-infinite-research/blob/v5.0.12/docs/support.md).
