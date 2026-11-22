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

MIR 5.0.23 fixes a worker cargo upgrade refusal and preserves unfinished research.

- On Factorio 2.0.77, upgrading MIR 4.7.3 with the unchanged official Space Age mods and default worker cargo settings preserves earned cargo, the previous science-pack requirements, queued levels and parked progress.
- Preserve recorded ownership of default worker cargo research through MIR 5 updates. Stop a worker cargo transfer if Factorio cannot supply the complete research queue.
- Keep the historical credit for unfinished recipe productivity and electric or Tesla research when the paid level is outside the queue.

Keep your original save and mod settings. Test the upgrade on a separate copy.

The worker cargo upgrade passed on Factorio 2.0.77. A separate Factorio 2.1.23 test resumed paid recipe productivity research from outside the queue and completed the level. The electric and Tesla save replay is pending. Library restart, wider compatibility and performance checks continue toward stable.

See the [support guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.23/docs/support.md) for supported editions and installation.
