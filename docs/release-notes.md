---
title: "MIR 5.0.25 beta release notes"
status: current
applies_to: "MIR 5.0.25 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-525-release-notes
---

This beta preserves earned worker cargo and unfinished research when a prepared save moves from Factorio 1.1.110 to 2.0.77.

- In Factorio 1.1.110, update MIR on a copy of your save. Run `/mir-worker-storage-recovery prepare`, save the paused game under a new name, and open that copy in Factorio 2.0.77 with the matching MIR edition and worker cargo settings.
- The verified upgrade keeps active and parked worker research at its original science price, preserves the research queue, and lets labs finish the remaining work normally.

[Supported editions and upgrade instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.25/docs/support.md#moving-a-factorio-11-save-to-20)

This is a GitHub beta. Library memory and performance qualification remains in progress.
