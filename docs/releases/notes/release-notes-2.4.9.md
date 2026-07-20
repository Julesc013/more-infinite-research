---
title: "MIR 2.4.9 Release Notes"
status: current
applies_to: "2.4.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-20
supersedes: []
superseded_by: []
---

# MIR 2.4.9 Release Notes

MIR 2.4.9 is a Factorio 2.0 stability update. It prevents unsupported `mod-data` output on the 2.0 engine, removes dangling technology-effect references for recipes, space locations, qualities, items, ammo categories, and turret entities, and keeps distinct `give-item` quality effects distinct. It also runs after Space Exploration's finalized recipe removals, preventing the removed Krastorio copper-cable recipe from remaining in a technology effect.

Configuration changes no longer trigger MIR's explicit force-wide technology-effect reset. This avoids reapplying unrelated research effects and better preserves custom recipe state owned by Factorio or other mods.

Steel productivity is now enabled for valid recipes producing steel plate. Base Factorio receives a stable MIR steel technology; Space Age keeps its native `steel-plate-productivity` technology as the single owner of `steel-plate` and `casting-steel`, with compatible additional steel outputs adopted when safe. Copper, iron, and steel families reject scrap-input recovery recipes so material recovery cannot become a second productivity loop.

The update preserves MIR 2.4.5 settings, existing generated research IDs, migrations, and runtime storage. The new steel family is an explicit stable stream, not automatic technology generation. The release makes no broader Pyanodon, Space Exploration, or Krastorio support claim.

The package now includes complete, consistently generated locale files for all 50 languages supported by Factorio. Locale checks keep every language synchronized with English and protect formatting placeholders, rich text, compact UI labels, and translated prose from regression.

Release qualification is bound to the exact 2.4.5 and 2.4.9 archives. All 106 machine-verifiable local checks pass for the final candidate, including 92 runtime scenarios, exact upgrade, ecosystem, approved-delta, deterministic package, locale, and paired performance checks. Package-focused maintainer review and protected qualification remain mandatory before the candidate can be sealed and published.
