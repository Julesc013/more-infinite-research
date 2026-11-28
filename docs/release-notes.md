---
title: "MIR 5.0.28 beta release notes"
status: current
applies_to: "MIR 5.0.28 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-28
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-528-release-notes
---

This beta improves research queue preservation, worker cargo upgrades and the Research Library.

- After a cap removes entries, MIR checks the remaining research queue and reports an error if Factorio changes it.
- Worker cargo transfers require a complete native research queue. Older upgrade refusals include the specific check that failed. Factorio help lists the worker cargo recovery commands.
- On Factorio 2.1 with Krastorio 2 Spaced Out, MIR checks every force before transferring Imersite research after a mod change.
- Upgrade diagnostics retain full mod names and versions.
- Startup dropdown options include their descriptions again. Revised descriptions use English where translations are pending.
- Searching Settings in the Research Library keeps your scroll position in Research.
- The mining drill research description clarifies that it increases manufacturing productivity. Placed drills follow Mining productivity and their own rules.

[Supported editions and upgrade instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.28/docs/support.md)

This is a GitHub beta. Matched Research Library timing and retained-memory verification are still in progress.
