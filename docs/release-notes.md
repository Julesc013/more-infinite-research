---
title: "MIR 5.0.4 beta release notes"
status: current
applies_to: "MIR 5.0.4 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-05
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-504-published-release-notes
---

This beta fixes research ownership conflicts while preserving previously earned bonuses.

- Avoid redundant weapon-speed research when compatible native research covers all its effects.
- Preserve electric and Tesla bonuses separately when native research covers only part of their shared upgrade.
- Avoid duplicate coal-crushing productivity with Galore while retaining earned sulfur bonuses and other sulfur effects.
- Handle research events whose technology is missing or no longer valid.

Use the ZIP matching your Factorio version. The modern packages require Factorio 2.0.77 or 2.1.23 respectively. Back up your save before updating and keep the previous package available.

Focused native checks cover the affected research, ownership changes, earned bonuses, queued work, force merges and save/reload boundaries on those exact modern engines. Different provider costs, prerequisites and science packs can change research work and availability. Provider changes that leave prerequisites unmet remain unqualified; keep the original save and mod selection for those transitions.

This is a GitHub prerelease. Full Library interaction/client acceptance and whole-product performance qualification remain unfinished.

The Factorio 0.18.47 package remains experimental/best effort; its native startup/crash smoke remains unverified. Early 0.6–0.12 packages are best effort and not natively qualified: extract their ZIP into that game's mods folder. They provide a fixed finite research subset without runtime features, settings, Library UI or migrations.
