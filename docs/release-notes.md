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

MIR 5.0.23 fixes worker robot storage save upgrades and preserves Space Exploration conquest bonuses alongside existing research.

- On Factorio 2.0.77, supported MIR 4.7.3 Space Age saves retain earned worker cargo capacity, paid science and queue order when upgraded with their original worker cargo settings.
- On Factorio 2.1.24 and 2.1.25, supported Space Age saves retain paid worker cargo research across the matching game and official mod update. Adding Solar Productivity 3.0.0 on Factorio 2.1.24 also preserves recorded worker cargo work.
- On Factorio 2.0.77 with Space Exploration 0.7.57, the staged legacy upgrade preserves completed research such as night vision and restores the conquest bonuses. Later supported add-on changes retain those bonuses.
- Preserve earned productivity and electric or Tesla research credit when the unfinished level is parked outside the research queue.
- Reopen the Research Library at the selected technology's new position when the list order changes.

Keep your original save. For legacy Space Exploration saves with earned or unfinished worker cargo research, apply the MIR and add-on changes in separate loads. Follow the [staged upgrade instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.23/docs/support.md#upgrading-mir-4720002-with-space-exploration).

See the [support guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.23/docs/support.md) for supported editions and installation.
