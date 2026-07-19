---
title: "MIR 2.4.9 Release Notes"
status: current
applies_to: "2.4.9"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-07-19
supersedes: []
superseded_by: []
---

# MIR 2.4.9 Release Notes

MIR 2.4.9 is a Factorio 2.0 stability update. It prevents unsupported `mod-data` output on the 2.0 engine, removes dangling technology-effect references for recipes, space locations, qualities, items, ammo categories, and turret entities, and keeps distinct `give-item` quality effects distinct.

Configuration changes no longer trigger MIR's explicit force-wide technology-effect reset. This avoids reapplying unrelated research effects and better preserves custom recipe state owned by Factorio or other mods.

The update preserves MIR 2.4.5 settings, generated research IDs, migrations, runtime storage, and default generated technology set. It does not enable new automatic technology generation or make broader Pyanodon, Space Exploration, or Krastorio support claims.

Release qualification is bound to the exact 2.4.5 and 2.4.9 archives. Runtime performance and package-focused manual review are mandatory before the candidate can be sealed and published.
