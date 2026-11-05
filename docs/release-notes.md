---
title: "MIR 5.0.6 beta release notes"
status: current
applies_to: "MIR 5.0.6 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-06
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-506-release-notes
---

This beta prevents unsafe Bob material research from consuming more science while preserving earned bonuses and unfinished work.

- Keep Bob material research unavailable when a recipe can return its own ingredients. On Factorio 2.1, remove that research from the active queue while retaining its partial progress and earned bonuses; eligible research continues normally.
- Restore conditional Marine coke research for Real Industrial Chemistry without changing its research owner or recipes.
- Preserve zero fluid-box extents when applying the pipeline-extent setting.

Use the ZIP matching your Factorio version. The modern packages require Factorio 2.0.77 or 2.1.23 respectively. Back up your save before updating and keep the previous package available.

Focused Factorio 2.1.23 full-Bob/Space Age checks start with bonuses earned in published 5.0.5, preserve paid and partial research through unavailability, and exercise a controlled recipe return. Eligible research and three new Tin levels complete normally; the configured cap, foreign force state, save and two cold reloads pass. These checks do not qualify physical Tin production, arbitrary provider changes or an entire modpack.

Real Industrial Chemistry runtime/save compatibility remains unverified: the available 0.35.8 archive fails upstream on Factorio 2.1.23 even without MIR, and 0.36.1 has not been natively checked.

This is a GitHub prerelease. Full Library interaction/client acceptance, historical reconciliation and whole-product performance qualification remain unfinished. Provider changes with unmet prerequisites remain unqualified; retain the original save and mod selection for those transitions.

The Factorio 0.18.47 package remains experimental/best effort; its native startup/crash smoke remains unverified. Early 0.6–0.12 packages are best effort and not natively qualified: extract their ZIP into that game's mods folder. They provide a fixed finite research subset without runtime features, settings, Library UI or migrations.
