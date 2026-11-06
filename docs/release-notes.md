---
title: "MIR 5.0.7 beta release notes"
status: current
applies_to: "MIR 5.0.7 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-06
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-507-release-notes
---

This beta preserves more earned research when updating older Base saves and fixes an upgrade check when moving from Factorio 2.0 to 2.1.

- Preserve earned low-density structure, plastic, processing-unit and rocket-fuel bonuses from MIR 1.0–1.2 Base saves.
- Preserve earned module bonuses when module research is disabled on the first updated load from MIR 1.1.
- Allow the reviewed MIR 4.7.3 Base upgrade from Factorio 2.0.77 to 2.1.23 without rejecting its known research ownership.
- Simplify player reports, local build instructions and source navigation, and update the API guide.

Use the ZIP matching your Factorio version. The modern packages require Factorio 2.0.77 or 2.1.23 respectively. Back up your save before updating and keep the previous package available.

Focused Base checks start from published MIR 1.0, 1.1, 1.2 and 4.7.3 saves. The affected earned bonuses, partial research and foreign force state survive the tested upgrades; new gear research, effects reset, save and cold reloads are checked on Factorio 2.0.77 and 2.1.23. The MIR 1.1 case also checks module research disabled on the first update. These are bounded save-preservation checks, not full historical or modpack qualification. Arbitrary scripted bonus offsets remain unqualified.

Real Industrial Chemistry runtime/save compatibility remains unverified: the available 0.35.8 archive fails upstream on Factorio 2.1.23 even without MIR, and 0.36.1 has not been natively checked.

This is a GitHub prerelease. Full Library interaction/client acceptance, historical reconciliation and whole-product performance qualification remain unfinished. Provider changes with unmet prerequisites remain unqualified; retain the original save and mod selection for those transitions.

The Factorio 0.18.47 package remains experimental/best effort; its native startup/crash smoke remains unverified. Early 0.6–0.12 packages are best effort and not natively qualified: extract their ZIP into that game's mods folder. They provide a fixed finite research subset without runtime features, settings, Library UI or migrations.
