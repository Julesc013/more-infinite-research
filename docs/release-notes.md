---
title: "MIR 5.0.5 beta release notes"
status: current
applies_to: "MIR 5.0.5 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-505-release-notes
---

This beta restores Space-policy research for a supported satellite-launch science source and corrects a German Library label.

- Keep research available on Factorio 2.1 with Space Age when the declared satellite-launch source supplies space science, while retaining its science gate.
- Correct the German Research Library sorting label.

Use the ZIP matching your Factorio version. The modern packages require Factorio 2.0.77 or 2.1.23 respectively. Back up your save before updating and keep the previous package available.

Focused Factorio 2.1.23 Space Age checks preserve earned gear bonuses, unfinished research, queued work and detached progress when updating from 5.0.4. Both the ordinary and controlled satellite-source cases complete another lab level, save and pass two cold reloads. These checks do not qualify physical satellite/science production or an entire modpack.

This is a GitHub prerelease. Full Library interaction/client acceptance, historical reconciliation and whole-product performance qualification remain unfinished. Provider changes with unmet prerequisites remain unqualified; retain the original save and mod selection for those transitions.

The Factorio 0.18.47 package remains experimental/best effort; its native startup/crash smoke remains unverified. Early 0.6–0.12 packages are best effort and not natively qualified: extract their ZIP into that game's mods folder. They provide a fixed finite research subset without runtime features, settings, Library UI or migrations.
