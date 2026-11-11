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

Fixes recurring worker cargo save upgrades and expanded recipe-productivity credits on Factorio 2.0 and 2.1.

- Preserve earned worker cargo research and unfinished work in permanent native research before adding a finite cargo provider. Eligible earlier MIR 5 default saves establish this history automatically when upgraded with their previous mods and settings.
- Keep private worker bookkeeping independent of the map research price multiplier while preserving ordinary research prices.
- Retain Secretas history across successive updates, Ferrum robotics science, and worker history through supported engine patch updates. Keep ordinary queue changes safe after preserved work finishes.
- Accept complete productivity-credit effect vectors added by recipe-expansion mods, while retaining validation of their recipes, signs and amounts.
- Allow Bob's Warfare with recipe-productivity-cap mods and preserve their configured caps.
- Preserve known Base-only research history on supported earlier MIR 5 upgrades.
- Restore missing translated startup-setting labels and improve Library wrapping, filters, title-bar controls and saved search text.

Before adding a worker cargo provider:

1. Protect the original save and its matching mods/settings. Update a copy to MIR 5.0.12 with the previous enabled mods and unchanged MIR settings, then save separately and exit.
2. Add the provider to that saved copy. Keep the worker enable setting and level cap unchanged while preserved work remains. Check cargo bonuses, current research and queue order before saving again.
3. If needed, `/mir-worker-storage-recovery resume <force-name>` appends detached partial work. The legacy `prepare` command is unnecessary once permanent native ownership is established.

An older save already changed and clamped by a provider needs its protected pre-change original. Repeated provider changes and arbitrary overhaul transitions remain unqualified. The known failure mechanisms have focused qualification; this does not establish that every reporter's complete modpack has been tested.

Script integrations should query `mir-worker-storage-default-4` for ordinary default cargo research. `worker-robots-storage-4` remains a separate prerequisite or foreign finite stage; see the [API guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.12/docs/api.md).

This is a GitHub beta. Library interaction/export/client-lifecycle and whole-product performance acceptance remain unfinished for stable.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.12/docs/support.md).
