---
title: "MIR 5.0.16 beta release notes"
status: current
applies_to: "MIR 5.0.16 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-16
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-516-release-notes
---

Improves settings-profile fidelity, compatibility checks and research-preservation diagnostics.

- Preserve settings-profile values and reject malformed supplied headers.
- Improve Bob/Angel material compatibility and Library availability explanations.
- Correct internal productivity-preservation costs on maps with custom research prices.
- Stop worker recovery after an unexpected application failure and explain when to reload the protected original.
- Name the rejecting mod and its old, new and active versions when a worker-cargo upgrade cannot authenticate its history.
- Report incomplete research setup immediately at startup.

Update a copy first. Keep a protected original save with its matching mods and startup settings. The additional worker-history details do not reconstruct missing ownership or earned research; some unprepared older saves can still be refused. Use the conditional recovery instructions in the support guide for a qualifying original default-worker save.

This is a GitHub beta. It does not include the unqualified Space Exploration level-10 worker-speed tail; its cap reset/continuation work remains deferred. Actual Library input/client checks and broader performance testing remain unfinished. No blanket save or modpack qualification is claimed.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.16/docs/support.md).
