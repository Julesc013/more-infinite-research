---
title: "MIR 5.0.23 beta release notes"
status: current
applies_to: "MIR 5.0.23 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-23
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-523-release-notes
---

MIR 5.0.23 fixes worker cargo upgrades and preserves credit for unfinished research.

- On Factorio 2.0.77 with the unchanged official Space Age mods and default worker cargo settings, upgrade a MIR 4.7.3 save with worker cargo, queued levels and unfinished research intact. The active level keeps its original six-pack price.
- Preserve a saved default worker cargo route across a same-edition MIR 5 upgrade. If the complete research queue is unavailable, stop the transfer before using the incomplete queue.
- Keep the historical credit owed to unfinished productivity and electric or Tesla research while the paid level is outside the queue.

Keep a copy of your original save before upgrading. Broader compatibility, personal-view persistence and performance qualification continue for stable.

See the [support guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.23/docs/support.md) for supported editions and installation.
