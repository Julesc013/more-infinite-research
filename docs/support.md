---
title: "Support and upgrade boundaries"
status: draft
applies_to: "MIR replacement development"
audience: maintainer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-25
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-support-guide
---

# Support and upgrade boundaries

## Current scope versus intention

The replacement is under development. This documentation does not announce a released MIR 5 package, completed migration, universal mod support or measured speedup. Use the actual published release and its stated limitations until a qualified replacement is available.

Stable replacement scope must retain delivered applicable research, settings, effects, native continuations, prototype overrides, scripted features, the Library, bundled integrations and each supported engine edition's actual subset. New unimplemented ideas remain the original backlog; they are not silently marked complete.

An ecosystem name is not a test result. Support records should identify exact Factorio and upstream versions/settings, whether the technology is present, researchable, effective, physically productive, upgrade-safe, reload-safe, multiplayer-tested and performance-measured. Load-only evidence is labelled load-only.

## Candidate editions

Factorio **2.1.23 stable (F210)** is the primary design and release target. Earlier MIR4 engine families retain best-effort editions with their actual supported subsets and the existing version encoding. Qualification records distinguish each edition's observed results and remaining gaps.

The [tracked edition record](../targets/editions.json) selects one self-contained player ZIP for each engine family. The following minimums come from the exact engines used by the qualification campaigns; they do not announce completed final-package acceptance. Select the same engine family when upgrading, rather than install another target's ZIP because its distribution number is larger.

| Target | Factorio family | Minimum base | MIR5 distribution |
|---|---|---|---|
| F210 | 2.1 | 2.1.23 | 5.0.21000 |
| F200 | 2.0 | 2.0.77 | 5.0.20000 |
| F110 | 1.1 | 1.1.110 | 5.0.11000 |
| F100 | 1.0 | 1.0.0 | 5.0.10000 |
| F017 | 0.17 | 0.17.79 | 5.0.01700 |
| F016 | 0.16 | 0.16.51 | 5.0.01600 |
| F015 | 0.15 | 0.15.40 | 5.0.01500 |
| F014 | 0.14 | 0.14.23 | 5.0.01400 |
| F013 | 0.13 | 0.13.20 | 5.0.01300 |

Modern targets expose recipe productivity and the Research Library. Expansion research requires its actual official mods and available science/labs. Historical editions retain their supported direct-effect subset; they do not acquire modern recipe productivity, Library or expansion capabilities. F013/F014 lack the later numeric infinite-level readback, and F013–F016 lack native research queues. The [research and settings reference](../README.md#research-catalog) retains the complete authored catalogue detail; exact profile admissions and omissions are named in the qualification records.

## First upgrade

Keep the original save, its pre-update backup, the selected mod archives and startup settings. Test a copy with the matching edition first. Preserve inherited settings for the first load; configuration changes and productivity-provider changes have separate transition requirements. Load, inspect earned research and bonuses, inspect current/queued or suspended work, save under a new name and cold-reload that copy before adopting it.

A cap below earned research limits future work without erasing earned levels. MIR restores only disablement it owns; another mod's configuration callback can independently reset technology state. Hidden migration carriers preserve named historical investments and must not be removed as cosmetic clutter. The retained [recovery guidance](../README.md#save-compatibility) and original incident records remain relevant to previously resaved factories: restoring a missing definition cannot reconstruct history already erased from a save.

Use the Research Library shortcut on modern targets to inspect research, queues, settings and availability. Its search/filter and language preferences belong to each player. Queue actions use native research behavior; the Library is not a second research planner. Startup settings take effect on the appropriate restart, and exporting a settings profile does not silently change the active game configuration.

## Safe diagnosis

Record Factorio/MIR version, exact archive identity where reissues existed, enabled mods/settings, the relevant log and a reproducible save when shareable. Preserve originals. Do not ask a player to repeatedly risk their only save, downgrade a resaved factory or disable a required mod as an assumed recovery.

For a new optional unsupported addition, MIR can omit that addition with a useful reason. Existing earned research requires a preservation/migration decision. A crash suppressed by deleting the technology is not a fix.

## Relevant retained incident subjects

Science trigger/output chains and independently available alternatives; specialist/resource science and labs; native-owner collisions; staged material/K2 progression; hidden credit carriers; caps and uncapping; foreign force offsets; manufacturing versus mining; settings imports and zero/inherit values; module/recycling safeguards; runtime registration; personal Library views and stale translations.

The original request/issue IDs and independent expected behavior must remain discoverable after source cleanup. Keep small current tests and pinned historical references, not old contradictory architecture documents in the active tree.

## Performance claims

Report whole-game startup separately from MIR-added startup. Headless creation/save, responsive menu, save load, first Library use and simulation are separate measurements. A one-technology demo or source-size reduction cannot establish the full replacement's performance. Missing data is inconclusive, not a proof of non-regression.
