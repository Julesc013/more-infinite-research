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

Fixes a worker cargo upgrade refusal when an existing MIR save retains default worker research after a mod change.

- Preserve earned robot cargo levels and current, queued and suspended work when a recorded MIR default route remains valid after adding, updating or removing other mods.
- Keep the original research price, including the map research price multiplier, during the transfer.

Back up your save and matching mods/settings before updating. Test the same-edition package on a copy with MIR startup settings unchanged. Unprepared changes that replace default worker research with another provider's finite research still require a qualified transfer from the protected original; this update cannot infer discarded history.

This is a GitHub beta. Library input/export/client-lifecycle checks and broader performance acceptance remain unfinished for stable.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.14/docs/support.md).
