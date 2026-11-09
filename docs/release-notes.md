---
title: "MIR 5.0.11 beta release notes"
status: current
applies_to: "MIR 5.0.11 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-09
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-511-release-notes
---

Fixes startup with fractional productivity rewards and adds preparation for worker cargo provider changes.

- Fix valid productivity reward settings causing startup errors on Factorio 2.0 and 2.1, including very small rewards.
- Retain the selected Library research while translated search results reload after changing tabs.
- Add an administrator/server command to prepare earned worker cargo bonuses and unfinished research before adding a finite cargo provider. Preparation covers the ordinary Base-game and Space Age worker research contract; the later provider transition remains under validation.

Before adding a worker cargo provider:

1. Protect the pre-change original save and its matching mods/settings. Load a copy with MIR 5.0.11 and the previous mod selection, then run `/mir-worker-storage-recovery prepare` as an administrator or server.
2. On success, save under a new name and exit immediately. Keep the worker level cap and enable setting unchanged through the provider change and while preserved work remains.
3. Add the intended provider to the prepared copy. Check cargo bonuses, current research and queue order before saving and reloading. Use `/mir-worker-storage-recovery resume <force-name>` to append detached partial work when needed.

An already-clamped save requires the pre-change original. Preparation for overhauls and repeated provider changes remains unqualified.

This is a GitHub beta with stable qualification unfinished. Full Ferrum-profile validation remains unverified because the required official mod archives were unavailable.

[Installation, preparation steps and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.11/docs/support.md).
