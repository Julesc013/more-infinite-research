---
title: "MIR 5.0.18 beta release notes"
status: current
applies_to: "MIR 5.0.18 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-518-release-notes
---

MIR 5.0.18 preserves earned and unfinished worker robot cargo research on supported upgrades and improves how the Research Library handles availability.

- On Factorio 2.0.77 with Space Exploration 0.7.57, keep the seven science packs and prerequisite used by saved paid cargo research. Ordinary lab research can resume when you raise the cap after completing the historical paid levels.
- On Factorio 2.1.24 with Krastorio 2: Spaced Out, preserve paid cargo work through the tested upgrade, a finite cap and a later cap increase. Restore unlimited silicon, glass and rare-metals productivity continuations when their research limit is set to zero.
- Retain earned recipe productivity when adding mods to a supported Base-only MIR 4.7.3 save with matching startup settings.
- Keep Library Availability scroll position when returning to the same results. Show when the queue, research list or prerequisites cannot be read, and restore counts and positions when the next read succeeds.
- Keep the right to restore earned research after a research-list read failure. Keep supported Bob and Angel research and ATAN startup available when MIR's minimum Factorio patch changes.

Update a copy and keep the original save with its previous mod versions and startup settings. MIR can still refuse an upgrade when it cannot establish the earlier cargo research history. Removing MIR, saving and adding it back risks discarding research data.

This GitHub beta covers the tested upgrades. Other reported save cases, remaining Research Library input and export checks, and broader performance acceptance remain open for stable MIR 5.

[Installation, upgrade precautions and support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.18/docs/support.md).
