---
title: "MIR 5.0.0 release notes"
status: current
applies_to: "MIR 5.0.0 first GitHub community beta"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-31
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-500-release-note-draft
---

- **Community beta:** simpler research generation, upgrade-preservation fixes and new Library settings/support exports. GitHub only; stable qualification continues.
- **Smaller download:** the Factorio 2.1 ZIP is 51.8% smaller than MIR 4.7.3. Packaged Lua drops from 47,755 to 28,105 lines.
- **Research and saves:** keeps existing research, settings and earned bonuses on supported upgrades, including older module and cannon bonuses. Caps limit future research without removing already-earned levels.
- **Compatibility:** restores missing Bob's/Angel's research and fixes science, progression and recipe bindings in supported Bob's/Angel's, Krastorio, Py and ATAN setups.
- **Research Library:** per-player search and filters, translated labels, and internal recovery technologies excluded from ordinary research.
- **Settings sharing on Factorio 2.0/2.1:** export full or compact profiles as a copyable string or text file. Full profiles are recommended for support requests.
- **Diagnostics on Factorio 2.0/2.1:** export a local support report from the Library. Attach Factorio's current log separately for startup or crash problems. Nothing uploads automatically.
- **Choose the matching download:** separate builds cover Factorio 0.13 through 2.1. Check the [minimum versions and supported features](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#candidate-editions).
- **Experimental older builds:** Factorio 0.18.47 remains experimental. The Factorio 0.6–0.12 builds contain basic finite research only, without mod settings, the Library or save migrations; they remain untested best effort. Unzip the Factorio 0.6–0.8 downloads as labelled.
- **Before upgrading:** back up the save and matching mods/settings. Test a copy with settings unchanged, inspect research and bonuses, then save and restart Factorio before adopting it. Read the [upgrade guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#first-upgrade) before changing Factorio versions or productivity-provider mods.
- **Already-lost research:** the 4.2.1 incident may require a pre-update backup; installing MIR 5 cannot reconstruct erased history. Follow the [recovery instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#recovery-from-the-421-incident).
- **Beta limits:** in-game verification of Library keyboard/focus behavior, saved personal views and export files is unfinished. Performance testing continues for heavy modpacks, large factories, save loading and Library memory; extreme loading delays remain under investigation.
- **Full changes:** see the [changelog](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/CHANGELOG.md).
- **Bug reports:** include Factorio/MIR versions, the mod list, a full settings profile, the engine log and a reproducible save where possible. See [support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/SUPPORT.md).

## Startup snapshot

- One included launch per MIR version/workload, with no-MIR launches before and after each group. No reboot or cache clearing; desktop applications stayed running.
- Intel Core i5-12600K, 32 GB RAM, Windows 10. Engines: Factorio 2.0.77 and 2.1.23.
- Seconds to the first observed main menu; a Settings interaction verifies responsiveness separately. Small differences are inconclusive in this single-pass snapshot. These are startup observations, not factory UPS measurements.

| MIR version | Factorio 2.1.23 Base: main menu (s) | Difference from no MIR (s) |
| --- | ---: | ---: |
| No MIR, final reference | 9.37 | — |
| MIR 2.2.0 | 9.40 | +0.04, inconclusive |
| MIR 3.2.11 | 10.01 | +0.64, inconclusive |
| MIR 4.7.3 | 10.03 | +0.66, inconclusive |
| MIR 5.0.0 beta | 9.31 | −0.05, inconclusive |

## Download and code size

| MIR release family | Factorio 2.0 ZIP (KiB) | Lua lines / files | Factorio 2.1 ZIP (KiB) | Lua lines / files |
| --- | ---: | ---: | ---: | ---: |
| MIR 1 | 93.1 | 1,505 / 10 | — | — |
| MIR 2 | 230.6 | 7,439 / 46 | 231.1 | 7,473 / 46 |
| MIR 3 | 1040.2 | 31,420 / 244 | 1042.7 | 31,638 / 246 |
| MIR 4.7.3 | 1415.5 | 46,493 / 283 | 1429.0 | 47,755 / 287 |
| MIR 5.0.0 beta | 688.1 | 28,105 / 114 | 688.4 | 28,105 / 114 |

- MIR 1 uses 1.2.9 on Factorio 2.0. MIR 2 uses 1.9.2 / 2.2.0; MIR 3 uses 2.5.11 / 3.2.11 for Factorio 2.0 / 2.1 respectively. MIR 1 has no Factorio 2.1 build.
- Lua counts include packaged authored data and comments. Files and lines describe code size and structure; they are not a complexity or performance score. Releases differ in features and supported content.
