---
title: "Support and upgrade boundaries"
status: current
applies_to: "MIR development"
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

Factorio **2.1 with minimum base 2.1.23 (F210)** is the primary design target. The normal editions retain their actual capability subsets and the existing version encoding, composed from shared source and narrow adapters. Every delivered edition requires final current-package and affected native qualification; records distinguish each edition's observed results and remaining gaps. Primary-target priority does not qualify an earlier edition or remove its release obligations.

The [tracked edition record](../targets/editions.json) selects one self-contained player ZIP for each engine family. The following are selected baseline engine minimums; they do not announce completed final-package acceptance. F018/0.18.47 is newly selected, with its source/build port integrated; actual all-science, forward-continuity and exact-engine/save qualification remain pending. Select the same engine family when upgrading, rather than install another target's ZIP because its distribution number is larger.

| Target | Factorio family | Minimum base | MIR5 distribution |
|---|---|---|---|
| F210 | 2.1 | 2.1.23 | 5.0.21000 |
| F200 | 2.0 | 2.0.77 | 5.0.20000 |
| F110 | 1.1 | 1.1.110 | 5.0.11000 |
| F100 | 1.0 | 1.0.0 | 5.0.10000 |
| F018 | 0.18 | 0.18.47 | 5.0.01800 — native qualification pending |
| F017 | 0.17 | 0.17.79 | 5.0.01700 |
| F016 | 0.16 | 0.16.51 | 5.0.01600 |
| F015 | 0.15 | 0.15.40 | 5.0.01500 |
| F014 | 0.14 | 0.14.23 | 5.0.01400 |
| F013 | 0.13 | 0.13.20 | 5.0.01300 |

Modern targets expose recipe productivity and the Research Library. Expansion research requires its actual official mods and available science/labs. Historical editions retain their supported direct-effect subset; they do not acquire modern recipe productivity, Library or expansion capabilities. F013/F014 lack the later numeric infinite-level readback, and F013–F016 lack native research queues. The [research and settings reference](../README.md#research-catalog) retains the complete authored catalogue detail; exact profile admissions and omissions are named in the qualification records.

## Additional best-effort historical builds

The separately selected [early-edition record](../targets/early-editions.json) builds F006/0.6.4, F007/0.7.5, F008/0.8.8, F009/0.9.8, F010/0.10.12, F011/0.11.22 and F012/0.12.35. These are data-only fixed finite research subsets recovered from the museum releases, with14/22/22/22/22/22/26 technologies respectively. They have no startup settings, runtime API, Library or migrations, and have not passed current native or save qualification. They are best-effort GitHub artifacts outside the normal-edition native acceptance claim. F006–F008 transport ZIPs require extraction into the engine mods folder; do not infer direct ZIP loading. Preserve original saves and installation files.

F001/0.1.2 and F002/0.2.10 lack an evidenced standalone-mod format. F003/0.3.2, F004/0.4.1 and F005/0.5.3 lack supplied exact engine/prototype inputs, so no build or native pass is claimed. F018/0.18.47 was excluded from the inherited baseline but is now selected as a normal edition, with source/build integration complete and actual native/forward-save qualification pending. Missing editions are recorded explicitly instead of filled with empty packages. The [target contract](../spec/targets.md#additional-historical-editions) owns these limits and their release disposition.

## First upgrade

Keep the original save, its pre-update backup, the selected mod archives and startup settings. Test a copy with the matching edition first. Preserve inherited settings for the first load; configuration changes and productivity-provider changes have separate transition requirements. Load, inspect earned research and bonuses, inspect current/queued or suspended work, save under a new name and cold-reload that copy before adopting it.

MIR 5 is still unreleased. Its required qualification includes 4.7.3 predecessor saves across supported editions and direct upgrades from every applicable published MIR 1.0.0-and-later origin on Factorio 2.0/2.1; this requirement is not a claim that those routes have all passed. The [migration scope](../spec/migrations.md#required-origin-coverage) separates exact same-engine upgrades, engine bridges and unavailable historical inputs. Later MIR 5 releases must retain tested direct upgrades from earlier MIR 5 saves for engine-valid origin/candidate pairs on supported editions. Earlier pre-5 origins on Factorio 1.1 and below remain best effort beyond the required 4.7.3 routes. Check the release's exact qualification and engine requirements before using a candidate on a real factory.

The candidate refuses a first published F2004.7 upgrade when earned overlapping productivity has no recorded MIR5 preference baseline, startup settings changed, and a known productivity provider is present or being removed. This also applies when moving directly from Factorio2.0 to2.1. Keep the original save: first evaluate the matching MIR5 F200 candidate on the original2.0 engine with the original mods and startup settings, then save and cold-reload that copy before changing the engine, provider or preference. The refusal protects research whose old preference cannot be inferred safely. The [migration policy](../spec/migrations.md#finite-transition-policy) distinguishes the observed4.7.2 two-step guard path, the separately passed C563 provider-free Base engine hop, and the still-unqualified4.7.3 settings/provider combinations. Each result retains its exact package and profile inputs.

A cap below earned research limits future work without erasing earned levels. MIR restores only disablement it owns; another mod's configuration callback can independently reset technology state. Hidden migration carriers preserve named historical investments and must not be removed as cosmetic clutter. The retained [recovery guidance](../README.md#save-compatibility) and original incident records remain relevant to previously resaved factories: restoring a missing definition cannot reconstruct history already erased from a save.

Use the Research Library shortcut on modern targets to inspect research, queues, settings and availability. Its search/filter and language preferences belong to each player. Queue actions use native research behavior; the Library is not a second research planner. Startup settings take effect on the appropriate restart, and exporting a settings profile does not silently change the active game configuration.

## Recovery from the 4.2.1 incident

This procedure retains the historical4.2.2 hotfix scope. It is not a MIR5 upgrade pass and does not change current edition requirements.

> **Upgrade and recovery:** Use the [4.2.2 hotfix](https://github.com/Julesc013/more-infinite-research/releases/tag/v4.2.2) directly from 4.2.0 or 4.2.1; do not install 4.2.1 as an intermediate step. Preserve original saves and pre-update backups. If you already saved after 4.2.1 removed research, restored definitions cannot recreate erased levels or bonuses: load a copy of your pre-update backup directly with 4.2.2 to retain that history. A whole backup returns the factory to its saved point. Do not remove MIR or downgrade an already-resaved factory as an assumed recovery. See [issue #621](https://github.com/Julesc013/more-infinite-research/issues/621) and the [hotfix notes](https://github.com/Julesc013/more-infinite-research/releases/download/v4.2.2/release-notes.md) for the tested scope and remaining limits.

## Safe diagnosis

Record Factorio/MIR version, exact archive identity where reissues existed, enabled mods/settings, the relevant log and a reproducible save when shareable. Preserve originals. Do not ask a player to repeatedly risk their only save, downgrade a resaved factory or disable a required mod as an assumed recovery.

For a new optional unsupported addition, MIR can omit that addition with a useful reason. Existing earned research requires a preservation/migration decision. A crash suppressed by deleting the technology is not a fix.

## Relevant retained incident subjects

Science trigger/output chains and independently available alternatives; specialist/resource science and labs; native-owner collisions; staged material/K2 progression; hidden credit carriers; caps and uncapping; foreign force offsets; manufacturing versus mining; settings imports and zero/inherit values; module/recycling safeguards; runtime registration; personal Library views and stale translations.

The original request/issue IDs and independent expected behavior must remain discoverable after source cleanup. Keep small current tests and pinned historical references, not old contradictory architecture documents in the active tree.

## Performance claims

Report whole-game startup separately from MIR-added startup. Headless creation/save, responsive menu, save load, first Library use and simulation are separate measurements. A one-technology demo or source-size reduction cannot establish the full replacement's performance. Missing data is inconclusive, not a proof of non-regression.
