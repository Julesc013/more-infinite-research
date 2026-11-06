---
title: "MIR 5.0.8 beta release notes"
status: current
applies_to: "MIR 5.0.8 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-07
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-508-release-notes
---

This beta restores the authored Research Library layout and fixes research-speed continuation when another mod supplies a finite level 7.

- Keep the title and tabs fixed when changing pages. Restore labelled research filters, compact benefit/requirements, the recipe pane, Settings fields and sectioned help.
- Preserve selection, scrolling and science-production snapshots during updates, and fix the narrow-layout resizing crash.
- Preserve external research-speed level 7 and continue MIR research from level 8, with earned bonuses and unfinished work protected.
- Show configured numeric caps in native research descriptions.
- Restore missing setting names, help and readable dropdown choices, retaining the authored translations.

Use the ZIP matching your Factorio version. Modern packages require Factorio 2.0.77 or 2.1.23 respectively. Back up your save and keep the previous package before updating.

If another mod supplies a finite research-speed level 7, keep the same mod selection, versions and startup settings for the first upgrade from MIR 4. MIR stops with recovery guidance when it cannot establish safe research ownership; restore the original save and previous selection if that happens. This old-save route is qualified only on the tested Factorio 2.1 setup, not Factorio 2.0 or every provider.

Focused checks cover actual research completion, earned bonuses, current/queued and paused work, unsafe first-upgrade refusals, cap changes, saving and cold reloads. In-game Library checks cover the restored normal-display layout, navigation and retained details. These are bounded results, not full modpack or historical qualification.

This is a GitHub prerelease. Remaining Library layouts, saved-view/client interaction, historical coverage and whole-product performance still need stable qualification. Real Industrial Chemistry runtime/save compatibility and the complete reported 564-mod selection remain unverified. Provider transitions with unmet prerequisites and arbitrary scripted bonus offsets remain unqualified.

Factorio 0.18.47 remains experimental/best effort. Early 0.6–0.12 packages are best effort and not natively qualified: extract their ZIP into that game's mods folder. They provide a fixed finite research subset without runtime features, settings, Library UI or migrations.
