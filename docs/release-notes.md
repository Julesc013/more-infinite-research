---
title: "MIR 5.0.24 beta release notes"
status: current
applies_to: "MIR 5.0.24 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-524-release-notes
---

This update preserves worker cargo research when Factorio replaces the queue and adds a way to recover paid research through a prepared Planet Ferrum removal and reinstall.

- Keep active and parked worker cargo progress at its recorded price during supported upgrades. Queued research keeps its order when Factorio replaces the native queue.
- With Factorio 2.1.25, Planet Ferrum 0.1.5 and PlanetsLib 2.4.0, prepare a copy of the save before removing the provider. After reinstall, MIR restores the saved work. If Factorio cleared a prerequisite, the paid research stays parked until it can resume. [Provider removal and resume steps](https://github.com/Julesc013/more-infinite-research/blob/v5.0.24/docs/support.md#removing-or-reinstalling-a-worker-cargo-provider)
- Read integer startup options without rounding. The Research Library skips subscription checks for unrelated interface actions.

Keep the original save and its mod selection when changing providers or upgrading from an older MIR version. [Supported editions and upgrade instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.24/docs/support.md)

This is a GitHub beta. Full Library and performance qualification remains in progress.
