---
title: "MIR 5.0.0 release notes"
status: draft
applies_to: "MIR 5.0.0 proposed first GitHub community beta"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-31
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-500-release-note-draft
---

- **MIR 5.0.0 community beta:** GitHub only. Stable qualification is still in progress.
- **Loading:** simpler research generation removes unnecessary startup work.
- **Research and saves:** keeps existing research, settings and earned bonuses on supported upgrades, including older module and cannon bonuses. Caps limit future research without removing already-earned levels.
- **Compatibility:** restores missing Bob's/Angel's research and fixes science, progression and recipe bindings in supported Bob's/Angel's, Krastorio, Py and ATAN setups.
- **Research Library:** keeps personal search, filters and translations; internal recovery technologies no longer appear as ordinary research.
- **Settings sharing on Factorio 2.0/2.1:** export full or compact profiles as a copyable string or text file. Full profiles are recommended for support requests.
- **Diagnostics on Factorio 2.0/2.1:** export a local support report from the Library. Attach Factorio's current log separately for startup or crash problems. Nothing uploads automatically.
- **Choose the matching download:** separate builds cover Factorio 0.13 through 2.1. Check the [minimum versions and supported features](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#candidate-editions).
- **Experimental older builds:** Factorio 0.18.47 remains experimental. The Factorio 0.6–0.12 builds contain basic finite research only, without mod settings, the Library or save migrations; they remain untested best effort. Unzip the Factorio 0.6–0.8 downloads as labelled.
- **Before upgrading:** back up the save and matching mods/settings. Test a copy with settings unchanged, inspect research and bonuses, then save and restart Factorio before adopting it. Read the [upgrade guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#first-upgrade) before changing Factorio versions or productivity-provider mods.
- **Already-lost research:** the 4.2.1 incident may require a pre-update backup; installing MIR 5 cannot reconstruct erased history. Follow the [recovery instructions](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/docs/support.md#recovery-from-the-421-incident).
- **Beta playtesting:** some Library controls, saved-view/rejoin behavior and settings/diagnostic exports still have unfinished checks. Please test these on a copied save and report problems.
- **Known limits:** performance testing continues for heavy modpacks, large active factories, save loading and Library memory. Final speed and memory claims are pending; extreme modpack loading delays remain under investigation.
- **Full changes:** see the [changelog](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/CHANGELOG.md).
- **Bug reports:** include Factorio/MIR versions, the mod list, a full settings profile, the engine log and a reproducible save where possible. See [support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.0/SUPPORT.md).
