---
title: "MIR 5.0.2 beta release notes"
status: draft
applies_to: "MIR 5.0.2 GitHub prerelease"
audience: player
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-03
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-502-release-note-draft
---

- **MIR 5.0.2 beta:** cumulative compatibility, saved-research and Research Library fixes. GitHub prerelease; stable qualification remains unfinished.
- **Compatibility:** avoid the duplicate weapon-speed research reported with Muria, retain its finite research, and preserve compatible infinite native research supplied by other mods. Refuse unsafe Muria addition or removal on an existing MIR save before changing MIR's saved state.
- **Discovery Tree:** respect research discovery in Library lists, details, queue labels and native research navigation. Keep private recovery research internal.
- **Saved research:** restore five historically paid manufacturing bonuses for affected Factorio 2.0 saves using Space Is Fake 1.0.60. Retain the published upgrade guidance, including the observed limitation for externally disabled research.
- **Library and settings:** show current and maximum recipe productivity, search recipe IDs, preview diagnostic exports, retain personal choices, restore older accepted imported settings values and English setting help, and correct three Russian research names.
- **Configurations checked:** selected Muria 1.9.5, Discovery Tree 1.0.12 and Science Spread 0.9.2 combinations on Factorio 2.1.23 completed affected research and save/reload checks. This does not establish compatibility with every mod combination or the reporter's entire mod list.
- **Beta limits:** full in-game Library input, saved-view/client lifecycle and actual export-file checks remain unfinished. Discovery Tree's None/reset interaction and its Library display still need visual verification. Whole-product large-factory performance and retained-memory testing remain open; no new general performance claim is made.
- **Before upgrading:** back up your save and test a copy with the same mods and settings. Follow the [upgrade guide](https://github.com/Julesc013/more-infinite-research/blob/v5.0.2/docs/support.md#first-upgrade).
- **Downloads:** choose the archive labelled for your Factorio version; each label states its minimum version. Factorio 0.18.47 is experimental, best effort and GitHub-only; its in-game load/crash check remains unverified.
- **Early downloads (Factorio 0.6–0.12):** finite Base research with fixed defaults only; no MIR runtime effects, mod settings, Research Library, runtime API or save migrations. These builds remain best effort and untested in-game. Unzip the Factorio 0.6–0.8 downloads into the mods folder.
- **Bug reports:** include Factorio and MIR versions, the complete mod list, settings, the current log and a reproducible save where possible. See [support](https://github.com/Julesc013/more-infinite-research/blob/v5.0.2/SUPPORT.md).
