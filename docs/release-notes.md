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

- One included launch per MIR version/workload on Factorio 2.0.77 and 2.1.23; no reboot or cache clearing. Desktop applications stayed running. Intel Core i5-12600K, 32 GB RAM, Windows 10.
- **Graphical initialization (seconds):** Factorio's normal graphical startup log, including mod, sound and graphics loading. This endpoint does not verify a responsive menu. The initial and final no-MIR launches are shown separately because cache/order effects were substantial.
- Heavy means Space Age plus the selected Bob's/Angel's mod set, including graphics packs. These are single-pass observations with different release features; small differences are inconclusive.

| MIR version | 2.0 Base | 2.0 Space Age | 2.0 heavy | 2.1 Base | 2.1 Space Age | 2.1 heavy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No MIR, initial launch | 14.46 | 45.72 | 40.22 | 12.86 | 30.24 | 42.06 |
| No MIR, final reference | 8.99 | 18.44 | 26.95 | 8.52 | 20.54 | 28.68 |
| MIR 1 | 9.17 | 18.44 | 27.24 | — | — | — |
| MIR 2 | 8.98 | 18.76 | 28.17 | 8.47 | 20.47 | 29.01 |
| MIR 3 | 10.31 | 19.92 | 31.35 | 9.05 | 22.09 | 33.00 |
| MIR 4.7.3 | 10.24 | 19.89 | 29.71 | 9.08 | 22.26 | 31.77 |
| MIR 5.0.0 beta | 9.04 | 19.13 | 28.00 | 8.28 | 20.66 | 28.88 |
| MIR 5 minus final no MIR | +0.06 | +0.69 | +1.05 | -0.24 | +0.11 | +0.21 |
| Seconds saved: MIR 4 to MIR 5 | 1.20 | 0.76 | 1.71 | 0.80 | 1.61 | 2.88 |

- The 2.1 heavy column uses retained initialization logs from runs whose menu checks failed. It remains a diagnostic comparison; those failures are not counted as menu passes.
- Signed differences are descriptive: a small negative value does not mean MIR makes Factorio faster than running without it. This snapshot cannot resolve small overheads reliably.
- **Observed main menu (seconds):** the following groups also passed a separate Settings response check. These times include the first observed menu, without adding the subsequent interaction-check delay.

| MIR version | 2.0.77 Base | 2.0.77 heavy Space Age | 2.1.23 Base |
| --- | ---: | ---: | ---: |
| No MIR, final reference | 9.90 | 27.98 | 9.37 |
| MIR 1 | 10.24 | 28.27 | — |
| MIR 2 | 10.01 | 29.10 | 9.40 |
| MIR 3 | 11.60 | 32.44 | 10.01 |
| MIR 4.7.3 | 11.07 | 30.62 | 10.03 |
| MIR 5.0.0 beta | 10.14 | 28.97 | 9.31 |

- MIR 5 reaches the observed menu about 0.7–1.6 seconds sooner than MIR 4.7.3 in these three snapshots. These results do not establish typical added startup cost or factory UPS; repeated controlled measurements remain pending.

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
