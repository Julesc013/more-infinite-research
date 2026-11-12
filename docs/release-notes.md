---
title: "MIR 5.0.13 beta release notes"
status: current
applies_to: "MIR 5.0.13 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-12
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-513-release-notes
---

Fixes multilingual Research Library searches while preserving the text you typed.

- Match Library searches using Factorio's native text handling, including non-English search text.
- Keep the original typed query when filtering and reopening Library views.

Back up your save and matching mods/settings before updating. Existing historical worker-upgrade limits remain; the separate extension for unfinished MIR 4.7.3 worker research is still under qualification and is not included in this patch.

This is a GitHub beta. Full Library input/export/client-lifecycle and whole-product performance acceptance remain unfinished for stable. Exact full reporter modpacks and arbitrary provider transitions are not claimed tested.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.13/docs/support.md).
